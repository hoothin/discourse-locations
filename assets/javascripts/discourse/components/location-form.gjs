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
import {
  cityOptionsByPrefecture,
  resolveCityName,
  resolvePrefectureName,
} from "../lib/jp-location-options";
import GeoLocationResult from "./geo-location-result";
import LocationSelector from "./location-selector";

const BROWSER_GEOLOCATION_SOURCE = "browser_geolocation";
const GEOLOCATION_PERMISSION_DENIED = 1;
const GEOLOCATION_POSITION_UNAVAILABLE = 2;
const GEOLOCATION_TIMEOUT = 3;
const GEOLOCATION_TIMEOUT_MS = 10000;

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
  @tracked browserLocationLoading = false;
  @tracked browserLocationError = null;

  context = null;
  cityDatalistId = `location-city-options-${Math.random().toString(36).slice(2)}`;

  showTitle = equal("appType", "discourse");

  constructor() {
    super(...arguments);
    this.context = this.args.context || null;
    this.formQuery = this.useRegionSelectors ? "" : this.args.rawLocation || "";
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

  get canUseAreaFallback() {
    return Boolean(
      this.useRegionSelectors &&
        String(this.formState || "").trim() &&
        String(this.formCity || "").trim()
    );
  }

  get cityOptions() {
    return cityOptionsByPrefecture(this.formState, this.formCity);
  }

  get coordinatesLocked() {
    return Boolean(this.args.coordinatesLocked);
  }

  get exactSearchDisabled() {
    return Boolean(this.searchDisabled || this.coordinatesLocked);
  }

  get browserLocationSupported() {
    return typeof navigator !== "undefined" && Boolean(navigator.geolocation);
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

  browserLocationErrorMessage(error) {
    switch (error?.code) {
      case GEOLOCATION_PERMISSION_DENIED:
        return i18n("location.geo.current.denied");
      case GEOLOCATION_POSITION_UNAVAILABLE:
        return i18n("location.geo.current.unavailable");
      case GEOLOCATION_TIMEOUT:
        return i18n("location.geo.current.timeout");
      default:
        return i18n("location.geo.current.error");
    }
  }

  @action
  useBrowserLocation() {
    if (!this.args.useBrowserGeolocation) {
      return;
    }

    if (!this.browserLocationSupported) {
      this.browserLocationError = i18n("location.geo.current.unsupported");
      return;
    }

    this.browserLocationLoading = true;
    this.browserLocationError = null;

    navigator.geolocation.getCurrentPosition(
      (position) => {
        if (this.isDestroying || this.isDestroyed) {
          return;
        }

        const latitude = position.coords.latitude;
        const longitude = position.coords.longitude;

        if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
          this.browserLocationLoading = false;
          this.browserLocationError = i18n("location.geo.current.unavailable");
          return;
        }

        const currentLocation = {
          lat: String(latitude),
          lon: String(longitude),
          source: BROWSER_GEOLOCATION_SOURCE,
          captured_at: new Date(position.timestamp || Date.now()).toISOString(),
        };

        if (Number.isFinite(position.coords.accuracy)) {
          currentLocation.accuracy = position.coords.accuracy;
        }

        this.formLatitude = currentLocation.lat;
        this.formLongitude = currentLocation.lon;
        this.geoLocationOptions = [];
        this.showLocationResults = false;
        this.browserLocationLoading = false;
        this.args.setGeoLocation(currentLocation);
      },
      (error) => {
        if (this.isDestroying || this.isDestroyed) {
          return;
        }

        this.browserLocationLoading = false;
        this.browserLocationError = this.browserLocationErrorMessage(error);
      },
      {
        enableHighAccuracy: true,
        maximumAge: 0,
        timeout: GEOLOCATION_TIMEOUT_MS,
      }
    );
  }

  @action
  clearSearch() {
    this.geoLocationOptions = [];
    this.args.geoLocation = null;
  }

  @action
  handleStateChange(value) {
    this.formState = value;
    if (!this.args.lockRegionFields) {
      this.formCity = "";
    }
    if (this.args.onStateChange) {
      this.args.onStateChange(value);
    }
  }

  @action
  handleCityChange(value) {
    this.formCity = resolveCityName(this.formState, value);
    if (this.args.onCityChange) {
      this.args.onCityChange(this.formCity);
    }
  }

  @action
  handleCityInput(event) {
    const value = resolveCityName(this.formState, event?.target?.value || "");
    this.formCity = value;
    if (this.args.onCityChange) {
      this.args.onCityChange(value);
    }
  }

  @action
  locationSearch() {
    if (this.coordinatesLocked) {
      return;
    }

    let request = {};

    if (this.useRegionSelectors) {
      const queryParts = [
        String(this.formPostalcode || "").trim(),
        String(this.formQuery || "").trim(),
        String(this.formCity || "").trim(),
        String(this.formState || "").trim(),
      ].filter(Boolean);
      request.query = queryParts.join(" ");
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
        this.geoLocationOptions = [];
        this.loadingLocations = false;
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
            {{#if this.useRegionSelectors}}
              <div class="location-region-grid">
                {{#if this.showState}}
                  <div class="location-field-row location-state-group">
                    <label class="control-label">{{i18n
                        "location.state.title"
                      }}</label>
                    <div class="controls">
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
                    </div>
                    <div class="instructions">{{i18n
                        "location.state.desc"
                      }}</div>
                  </div>
                {{/if}}
                {{#if this.showCity}}
                  <div class="location-field-row location-city-group">
                    <label class="control-label">{{i18n
                        "location.city.title"
                      }}</label>
                    <div class="controls">
                      <Input
                        @type="text"
                        @value={{this.formCity}}
                        list={{this.cityDatalistId}}
                        class="input-large input-location city-input"
                        disabled={{this.citySelectDisabled}}
                        {{on "input" this.handleCityInput}}
                      />
                      <datalist id={{this.cityDatalistId}}>
                        {{#each this.cityOptions as |city|}}
                          <option value={{city.name}}></option>
                        {{/each}}
                      </datalist>
                    </div>
                    <div class="instructions">{{i18n "location.city.desc"}}</div>
                  </div>
                {{/if}}
              </div>
              <div class="location-exact-grid">
                {{#if this.showPostalcode}}
                  <div class="location-field-row location-postal-group">
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
                {{#if this.showGeoLocation}}
                  <div class="location-field-row location-query-group">
                    <label class="control-label">{{i18n
                        "location.query.title"
                      }}</label>
                    <div class="controls">
                      <Input
                        @type="text"
                        @value={{this.formQuery}}
                        class="input-xxlarge input-location"
                      />
                    </div>
                    <div class="instructions">{{i18n "location.query.desc"}}</div>
                  </div>
                  <div class="location-field-row location-search-group">
                    <label class="control-label">&nbsp;</label>
                    <div class="controls">
                      <div class="location-search-actions">
                        <button
                          class="btn btn-default wizard-btn location-search"
                          {{on "click" this.locationSearch}}
                          disabled={{this.exactSearchDisabled}}
                          type="button"
                        >
                          {{i18n "location.geo.btn.label"}}
                        </button>
                        {{#if @useBrowserGeolocation}}
                          <button
                            class="btn btn-default wizard-btn location-current"
                            {{on "click" this.useBrowserLocation}}
                            disabled={{this.browserLocationLoading}}
                            type="button"
                          >
                            {{#if this.browserLocationLoading}}
                              {{i18n "location.geo.current.loading"}}
                            {{else}}
                              {{i18n "location.geo.current.label"}}
                            {{/if}}
                          </button>
                        {{/if}}
                      </div>
                    </div>
                    {{#if this.coordinatesLocked}}
                      <div class="location-gps-status">{{i18n
                          "location.geo.current.locked"
                        }}</div>
                    {{/if}}
                    {{#if this.browserLocationError}}
                      <div class="location-gps-error">
                        {{this.browserLocationError}}
                      </div>
                    {{/if}}
                  </div>
                {{/if}}
              </div>
              {{#if this.showGeoLocation}}
                {{#if this.showLocationResults}}
                  {{#unless this.coordinatesLocked}}
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
                              {{#if this.canUseAreaFallback}}
                                <li class="no-results area-fallback">{{i18n
                                    "location.geo.area_fallback"
                                  }}</li>
                              {{/if}}
                            {{/each}}
                          </ConditionalLoadingSpinner>
                        {{/if}}
                      </ul>
                    </div>
                    {{#if this.showProvider}}
                      <div class="location-form-instructions">{{htmlSafe
                          (i18n
                            "location.geo.desc"
                            provider=this.providerDetails
                          )
                        }}</div>
                    {{/if}}
                  {{/unless}}
                {{/if}}
              {{/if}}
            {{else}}
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
              {{#unless this.useRegionSelectors}}
                <button
                  class="btn btn-default wizard-btn location-search"
                  {{on "click" this.locationSearch}}
                  disabled={{this.exactSearchDisabled}}
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
                            {{#if this.canUseAreaFallback}}
                              <li class="no-results area-fallback">{{i18n
                                  "location.geo.area_fallback"
                                }}</li>
                            {{/if}}
                          {{/each}}
                        </ConditionalLoadingSpinner>
                      {{/if}}
                    </ul>
                  </div>
                  {{#if this.showProvider}}
                    <div class="location-form-instructions">{{htmlSafe
                        (i18n
                          "location.geo.desc"
                          provider=this.providerDetails
                        )
                      }}</div>
                  {{/if}}
                {{/if}}
              {{/unless}}
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
                disabled={{this.coordinatesLocked}}
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
                disabled={{this.coordinatesLocked}}
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
