import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { Input } from "@ember/component";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action, set } from "@ember/object";
import { equal } from "@ember/object/computed";
import { service } from "@ember/service";
import { htmlSafe } from "@ember/template";
import { hash } from "rsvp";
import ConditionalLoadingSpinner from "discourse/components/conditional-loading-spinner";
import { ajax } from "discourse/lib/ajax";
import ComboBox from "discourse/select-kit/components/combo-box";
import { i18n } from "discourse-i18n";
import { geoLocationSearch, providerDetails } from "../lib/location-utilities";
import { resolvePrefectureName } from "../lib/jp-location-options";
import GeoLocationResult from "./geo-location-result";
import LocationSelector from "./location-selector";

export default class LocationForm extends Component {
  @service siteSettings;
  @service site;

  @tracked geoLocationOptions = [];
  @tracked internalInputFields = [];
  @tracked provider = "";
  @tracked hasSearched = false;
  @tracked searchDisabled = false;
  @tracked showProvider = false;
  @tracked showGeoLocation = true;
  @tracked countrycodes = [];
  @tracked loadingLocations = false;
  @tracked showLocationResults = false;
  @tracked formStreet;
  @tracked formNeighbourhood;
  @tracked formPostalcode;
  @tracked formCity;
  @tracked formState;
  @tracked formQuery;
  @tracked formCountrycode;
  @tracked formLatitude;
  @tracked formLongitude;
  @tracked geoLocation = {};

  context = null;

  showTitle = equal("appType", "discourse");

  constructor() {
    super(...arguments);
    this.context = this.args.context || null;
    this.formQuery = this.args.rawLocation || "";
    this.formCountrycode =
      this.args.countrycode ||
      this.siteSettings.location_country_default ||
      "jp";

    if (this.showInputFields) {
      this.internalInputFields = this.args.inputFields;

      this.searchDisabled = true;

      this.internalInputFields.forEach((f) => {
        this[`show${f.charAt(0).toUpperCase() + f.substr(1).toLowerCase()}`] =
          true;
        this[`form${f.charAt(0).toUpperCase() + f.substr(1).toLowerCase()}`] =
          this.args[f];

        if (["street", "neighbourhood", "postalcode", "city"].includes(f)) {
          this.searchDisabled = false;
        }
      });
      if (this.useRegionSelectors) {
        this.searchDisabled = false;
      }

      if (this.args.disabledFields) {
        this.args.disabledFields.forEach((f) => {
          this.set(`${f}Disabled`, true);
        });
      }

      const hasCoordinates =
        this.internalInputFields.indexOf("coordinates") > -1;

      if (hasCoordinates && this.args.geoLocation) {
        this.formLatitude = this.args.geoLocation.lat;
        this.formLongitude = this.args.geoLocation.lon;
      }

      const geocoding = this.siteSettings.location_geocoding;
      this.showGeoLocation = geocoding !== "none";
      this.showLocationResults = geocoding === "required";

      if (this.searchOnInit) {
        this.send("locationSearch");
      }
    }

    const siteCodes = this.site.country_codes;

    if (siteCodes) {
      this.countrycodes = siteCodes;
    } else {
      ajax({
        url: "/locations/countries",
        type: "GET",
      }).then((result) => {
        this.countrycodes = result.geo;
      });
    }
  }

  get showInputFields() {
    if (this.args.inputFieldsEnabled === false) {
      return false;
    }
    return (
      this.args.inputFieldsEnabled ||
      this.siteSettings.location_input_fields_enabled
    );
  }

  get showAddress() {
    return (
      !this.showInputFields ||
      (this.showInputFields &&
        this.internalInputFields.filter((f) => f !== "coordinates").length > 0)
    );
  }

  get useRegionSelectors() {
    return Boolean(this.args.useRegionSelectors);
  }

  get stateSelectDisabled() {
    return Boolean(this.stateDisabled || this.args.lockRegionFields);
  }

  get citySelectDisabled() {
    return Boolean(this.cityDisabled || this.args.lockRegionFields);
  }

  get providerDetails() {
    return providerDetails[
      this.provider || this.siteSettings.location_geocoding_provider
    ];
  }

  keyDown(e) {
    if (this.showGeoLocation && e.keyCode === 13) {
      this.send("locationSearch");
    }
  }

  get searchLabel() {
    return i18n(`location.geo.btn.${this.siteSettings.location_geocoding}`);
  }

  @action
  updateGeoLocation(gl, force_coords) {
    gl["zoomTo"] = true;

    if (force_coords) {
      gl.lat = this.formLatitude;
      gl.lon = this.formLongitude;
    } else {
      this.formLatitude = gl.lat;
      this.formLongitude = gl.lon;
    }

    if (
      gl.address &&
      this.siteSettings.location_auto_infer_street_from_address_data &&
      gl.address.indexOf(gl.city) > 0
    ) {
      gl.street = gl.address
        .slice(0, gl.address.indexOf(gl.city))
        .replace(/,(\s+)?$/, "");
    }

    this.internalInputFields.forEach((f) => {
      if (f === "coordinates") {
        this.formLatitude = gl.lat;
        this.formLongitude = gl.lon;
      } else {
        this[`form${f.charAt(0).toUpperCase() + f.substr(1).toLowerCase()}`] =
          gl[f];
      }
    });
    if (this.useRegionSelectors) {
      const inferredStateFromAddress =
        String(gl.address || "").match(
          /(東京都|北海道|(?:京都|大阪)府|[^都道府県县縣\s,，]{1,8}[県县縣])/
        )?.[1] || "";
      const resolvedState = resolvePrefectureName(
        gl.state ||
          gl.province ||
          gl.region ||
          gl.county ||
          inferredStateFromAddress
      );
      const resolvedCity = gl.city || gl.district || "";
      this.formState = resolvedState || "";
      this.formCity = String(resolvedCity).trim();
    }

    this.args.setGeoLocation(gl);
    this.geoLocationOptions.forEach((o) => {
      set(o, "selected", o["address"] === gl["address"]);
    });
  }

  @action
  clearSearch() {
    this.geoLocationOptions = [];
    this.args.geoLocation = null;
  }

  @action
  handleStateChange(value) {
    this.formState = value;
    if (this.args.onStateChange) {
      this.args.onStateChange(value);
    }
  }

  @action
  handleCityChange(value) {
    this.formCity = value;
    if (this.args.onCityChange) {
      this.args.onCityChange(value);
    }
  }

  @action
  handleCityInput(event) {
    const value = event?.target?.value || "";
    this.formCity = value;
    if (this.args.onCityChange) {
      this.args.onCityChange(value);
    }
  }

  @action
  locationSearch() {
    let request = {};

    if (this.useRegionSelectors) {
      request.query = String(this.formQuery || "").trim();
      request.countrycode = this.formCountrycode;
      request.context = this.context;
      request.language = "ja";
      if (this.formState) request.state = this.formState;
      if (this.formCity) request.city = this.formCity;
    } else {
      const searchInputFields = this.internalInputFields.concat([
        "countrycode",
        "context",
      ]);
      searchInputFields.map((f) => {
        request[f] =
          this[`form${f.charAt(0).toUpperCase() + f.substr(1).toLowerCase()}`];
        if (f === "coordinates") {
          request["lat"] = this.formLatitude;
          request["lon"] = this.formLongitude;
        }
      });
    }

    if (
      !Object.values(request).some(
        (value) => value !== undefined && value !== ""
      )
    ) {
      return;
    }

    if (this.useRegionSelectors && !request.query) {
      if (this.formCity || this.formState) {
        request.query = [this.formCity, this.formState].filter(Boolean).join(" ");
      }
    }

    this.showLocationResults = true;
    this.loadingLocations = true;
    this.hasSearched = true;
    this.showProvider = false;

    geoLocationSearch(request, this.siteSettings.location_geocoding_debounce)
      .then((result) => {
        if (this._state === "destroying") {
          return;
        }

        if (result.error) {
          throw new Error(result.error);
        }

        if (result.provider) {
          this.provider = result.provider;
        }

        const normalizeAddress = (value) =>
          String(value || "")
            .trim()
            .toLowerCase()
            .replace(/[，､]/g, ",")
            .replace(/\s+/g, " ");
        const seen = new Set();
        const dedupedLocations = (result.locations || []).filter((location) => {
          const normalizedAddress = normalizeAddress(location.address);
          const key =
            normalizedAddress ||
            [String(location.lat || "").trim(), String(location.lon || "").trim()].join("|");
          if (seen.has(key)) {
            return false;
          }
          seen.add(key);
          return true;
        });

        this.showProvider = dedupedLocations.length > 0;
        this.geoLocationOptions = [...dedupedLocations];

        this.loadingLocations = false;
      })
      .catch((error) => {
        this.args.searchError(error);
      });
  }

  <template>
    <div class="location-form">
      {{#if this.showAddress}}
        <div class="address">
          {{#if this.showInputFields}}
            {{#if this.showTitle}}
              <div class="title">
                {{i18n "location.address"}}
              </div>
            {{/if}}
            {{#if this.showStreet}}
              <div class="control-group">
                <label class="control-label">{{i18n
                    "location.street.title"
                  }}</label>
                <div class="controls">
                  <Input
                    @type="text"
                    @value={{this.formStreet}}
                    class="input-large input-location"
                    disabled={{this.streetDisabled}}
                  />
                </div>
                <div class="instructions">{{i18n "location.street.desc"}}</div>
              </div>
            {{/if}}
            {{#if this.showNeighbourhood}}
              <div class="control-group">
                <label class="control-label">{{i18n
                    "location.neighbourhood.title"
                  }}</label>
                <div class="controls">
                  <Input
                    @value={{this.formNeighbourhood}}
                    class="input-large input-location"
                    disabled={{this.neighbourhoodDisabled}}
                  />
                </div>
                <div class="instructions">{{i18n
                    "location.neighbourhood.desc"
                  }}</div>
              </div>
            {{/if}}
            {{#if this.showPostalcode}}
              <div class="control-group">
                <label class="control-label">{{i18n
                    "location.postalcode.title"
                  }}</label>
                <div class="controls">
                  <Input
                    @type="text"
                    @value={{this.formPostalcode}}
                    class="input-small input-location"
                    disabled={{this.postalcodeDisabled}}
                  />
                </div>
                <div class="instructions">{{i18n
                    "location.postalcode.desc"
                  }}</div>
              </div>
            {{/if}}
            {{#if this.showState}}
              {{#if this.useRegionSelectors}}
                <div class="control-group">
                  <label class="control-label">{{i18n "location.query.title"}}</label>
                  <div class="controls">
                    <Input
                      @type="text"
                      @value={{this.formQuery}}
                      class="input-xxlarge input-location"
                    />
                  </div>
                  <div class="instructions">{{i18n "location.query.desc"}}</div>
                </div>
              {{/if}}
              <div class="control-group">
                <label class="control-label">{{i18n
                    "location.state.title"
                  }}</label>
                <div class="controls">
                  {{#if this.useRegionSelectors}}
                    <ComboBox
                      @valueProperty="code"
                      @nameProperty="name"
                      @content={{@stateOptions}}
                      @value={{this.formState}}
                      class="input-location prefecture-select"
                      @onChange={{this.handleStateChange}}
                      @options={{hash
                        filterable="true"
                        disabled=this.stateSelectDisabled
                        none="location.state.title"
                      }}
                    />
                  {{else}}
                    <Input
                      @value={{this.formState}}
                      class="input-large input-location"
                      disabled={{this.stateDisabled}}
                    />
                  {{/if}}
                </div>
                <div class="instructions">{{i18n "location.state.desc"}}</div>
              </div>
            {{/if}}
            {{#if this.showCity}}
              <div class="control-group">
                <label class="control-label">{{i18n
                    "location.city.title"
                  }}</label>
                <div class="controls">
                  {{#if this.useRegionSelectors}}
                    <Input
                      @type="text"
                      @value={{this.formCity}}
                      class="input-large input-location city-input"
                      disabled={{this.citySelectDisabled}}
                      {{on "input" this.handleCityInput}}
                    />
                  {{else}}
                    <Input
                      @type="text"
                      @value={{this.formCity}}
                      class="input-large input-location"
                      disabled={{this.cityDisabled}}
                    />
                  {{/if}}
                </div>
                <div class="instructions">{{i18n "location.city.desc"}}</div>
              </div>
            {{/if}}
            {{#if this.showCountrycode}}
              <div class="control-group">
                <label class="control-label">{{i18n
                    "location.country_code.title"
                  }}</label>
                <div class="controls">
                  <ComboBox
                    @valueProperty="code"
                    @nameProperty="name"
                    @content={{this.countrycodes}}
                    @value={{this.formCountrycode}}
                    class="input-location country-code"
                    @onChange={{fn (mut this.formCountrycode)}}
                    @options={{hash
                      filterable="true"
                      disabled=this.countryDisabled
                      none="location.country_code.placeholder"
                    }}
                  />
                </div>
              </div>
            {{/if}}
          {{else}}
            <div class="control-group">
              <label class="control-label">{{i18n
                  "location.query.title"
                }}</label>
              <div class="controls location-selector-container">
                {{#if this.showGeoLocation}}
                  <LocationSelector
                    @location={{this.geoLocation}}
                    @onChangeCallback={{this.updateGeoLocation}}
                    class="input-xxlarge location-selector"
                    @searchError={{@searchError}}
                    @context={{this.context}}
                    @geoAttrs={{@geoAttrs}}
                    @showType={{@showType}}
                  />
                {{else}}
                  <Input
                    @type="text"
                    @value={{this.rawLocation}}
                    class="input-xxlarge input-location"
                  />
                {{/if}}
              </div>
              <div class="instructions">
                {{i18n "location.query.desc"}}
              </div>
            </div>
          {{/if}}
          {{#if this.showGeoLocation}}
            {{#if this.showInputFields}}
              <button
                class="btn btn-default wizard-btn location-search"
                {{on "click" this.locationSearch}}
                disabled={{this.searchDisabled}}
                type="button"
              >
                {{i18n "location.geo.btn.label"}}
              </button>
              {{#if this.showLocationResults}}
                <div class="location-results">
                  <h4>{{i18n "location.geo.results"}}</h4>
                  <ul>
                    {{#if this.hasSearched}}
                      <ConditionalLoadingSpinner
                        @condition={{this.loadingLocations}}
                      >
                        {{#each this.geoLocationOptions as |l|}}
                          <GeoLocationResult
                            @updateGeoLocation={{this.updateGeoLocation}}
                            @location={{l}}
                            @geoAttrs={{this.geoAttrs}}
                          />
                        {{else}}
                          <li class="no-results">{{i18n
                              "location.geo.no_results"
                            }}</li>
                        {{/each}}
                      </ConditionalLoadingSpinner>
                    {{/if}}
                  </ul>
                </div>
                {{#if this.showProvider}}
                  <div class="location-form-instructions">{{htmlSafe
                      (i18n "location.geo.desc" provider=this.providerDetails)
                    }}</div>
                {{/if}}
              {{/if}}
            {{/if}}
          {{/if}}
        </div>
      {{/if}}

      {{#if this.showCoordinates}}
        <div class="coordinates">
          <div class="title">
            {{i18n "location.coordinates"}}
          </div>
          <div class="control-group">
            <label class="control-label">{{i18n "location.lat.title"}}</label>
            <div class="controls">
              <Input
                @type="number"
                @value={{this.formLatitude}}
                {{on
                  "change"
                  (fn this.updateGeoLocation this.geoLocation true)
                }}
                {{on
                  "onKepyUp"
                  (fn this.updateGeoLocation this.geoLocation true)
                }}
                step="any"
                class="input-small input-location lat"
              />
              <div class="icon">
                <img src="/plugins/discourse-locations/images/latitude.png" />
              </div>
            </div>
            <div class="instructions">
              {{i18n "location.lat.desc"}}
            </div>
          </div>
          <div class="control-group">
            <label class="control-label">{{i18n "location.lon.title"}}</label>
            <div class="controls">
              <Input
                @type="number"
                @value={{this.formLongitude}}
                {{on
                  "change"
                  (fn this.updateGeoLocation this.geoLocation true)
                }}
                {{on
                  "onKepyUp"
                  (fn this.updateGeoLocation this.geoLocation true)
                }}
                step="any"
                class="input-small input-location lon"
              />
              <div class="icon">
                <img src="/plugins/discourse-locations/images/longitude.png" />
              </div>
            </div>
            <div class="instructions">
              {{i18n "location.lon.desc"}}
            </div>
          </div>
        </div>
      {{/if}}
    </div>
  </template>
}
