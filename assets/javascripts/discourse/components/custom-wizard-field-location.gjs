import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { array } from "@ember/helper";
import { action, computed } from "@ember/object";
import { service } from "@ember/service";
import { i18n } from "discourse-i18n";
import {
  prefectureOptions,
  resolvePrefectureName,
} from "../lib/jp-location-options";
import LocationForm from "./location-form";

const BROWSER_GEOLOCATION_SOURCE = "browser_geolocation";

export default class CustomWizardFieldLocationComponent extends Component {
  @service siteSettings;

  @tracked name = null;
  @tracked street = null;
  @tracked postalcode = null;
  @tracked city = null;
  @tracked state = null;
  @tracked countrycode = null;
  @tracked geoLocation = { lat: "", lon: "" };
  @tracked rawLocation = null;
  @tracked lockRegionFields = false;
  @tracked gpsLocked = false;
  @tracked gpsAccuracy = null;
  @tracked gpsCapturedAt = null;
  context = this.args.wizard.id;
  includeGeoLocation = true;
  inputFieldsEnabled = true;
  layoutName = "javascripts/wizard/templates/components/wizard-field-location";

  constructor() {
    super(...arguments);
    const existing = this.args.field.value || {};
    const inputFields = this.inputFields;

    inputFields.forEach((f) => {
      if (existing[f]) {
        this[f] = existing[f];
      }
    });

    this.geoLocation = existing["geo_location"] || {};
    this.rawLocation = existing["address"] || existing["raw_location"] || null;
    this.countrycode =
      this.countrycode || this.siteSettings.location_country_default || "jp";
    this.gpsLocked = this.isBrowserGeolocation(existing);
    this.gpsAccuracy = existing["accuracy"] || null;
    this.gpsCapturedAt = existing["captured_at"] || null;
    this.args.field.customCheck = this.customCheck.bind(this);
  }

  customCheck() {
    const required = this.args.field.required;
    const hasInput = this.inputFields.some((f) => this[f]);

    if (required || hasInput) {
      return this.handleValidation();
    } else {
      return true;
    }
  }

  @computed
  get inputFields() {
    const fields = this.siteSettings.location_input_fields
      .split("|")
      .filter(Boolean);

    return Array.from(new Set([...fields, "state", "city"]));
  }

  @computed("state")
  get stateOptions() {
    return prefectureOptions();
  }

  extractJapanesePrefecture(address) {
    const text = String(address || "");
    if (!text) return "";
    const match = text.match(
      /(東京都|北海道|(?:京都|大阪)府|[^都道府県县縣\s,，]{1,8}[県县縣])/
    );
    return match ? match[1] : "";
  }

  inferStateFromRawLocation() {
    if (this.state) return;
    const inferred = this.extractJapanesePrefecture(this.rawLocation);
    if (inferred) {
      this.state = inferred;
    }
  }

  hasGeoCoordinates() {
    return Boolean(
      this.compactText(this.geoLocation?.lat) &&
        this.compactText(this.geoLocation?.lon)
    );
  }

  compactText(value) {
    return value === null || value === undefined ? "" : String(value).trim();
  }

  isBrowserGeolocation(location) {
    return Boolean(
      location &&
        (location.source === BROWSER_GEOLOCATION_SOURCE ||
          location.precision === "gps" ||
          location.gps_locked === true ||
          location.gps_locked === "true")
    );
  }

  buildGeoLocationValue() {
    return {
      lat: this.compactText(this.geoLocation?.lat),
      lon: this.compactText(this.geoLocation?.lon),
    };
  }

  buildAreaAddress() {
    return [this.state, this.city]
      .map((value) => this.compactText(value))
      .filter(Boolean)
      .join(" ");
  }

  buildLocationValue(extraAttrs = {}) {
    const location = {};

    this.inputFields.forEach((field) => {
      const value = this.compactText(this[field]);
      if (value) {
        location[field] = value;
      }
    });

    location.countrycode = this.compactText(this.countrycode || "jp") || "jp";
    location.address =
      this.compactText(this.rawLocation) || this.buildAreaAddress();
    location.precision = this.hasGeoCoordinates() ? "exact" : "area";

    if (this.hasGeoCoordinates()) {
      location.geo_location = this.buildGeoLocationValue();
    }

    if (this.gpsLocked) {
      location.precision = "exact";
      location.source = BROWSER_GEOLOCATION_SOURCE;
      location.gps_locked = true;

      if (
        this.gpsAccuracy !== null &&
        this.gpsAccuracy !== undefined &&
        this.compactText(this.gpsAccuracy)
      ) {
        const accuracy = Number(this.gpsAccuracy);
        if (Number.isFinite(accuracy)) {
          location.accuracy = accuracy;
        }
      }

      const capturedAt = this.compactText(this.gpsCapturedAt);
      if (capturedAt) {
        location.captured_at = capturedAt;
      }
    }

    return { ...location, ...extraAttrs };
  }

  syncFieldValue() {
    this.args.field.value = this.buildLocationValue();
  }

  handleValidation() {
    this.inferStateFromRawLocation();

    if (this.gpsLocked && !this.hasGeoCoordinates()) {
      return this.setValidation(false, "coordinates");
    }

    if (
      this.inputFieldsEnabled &&
      this.inputFields.indexOf("coordinates") > -1 &&
      (this.geoLocation.lat || this.geoLocation.lon)
    ) {
      return this.setValidation(
        this.geoLocation.lat && this.geoLocation.lon,
        "coordinates"
      );
    }

    if (this.inputFieldsEnabled && !this.compactText(this.state)) {
      return this.setValidation(false, "state");
    }

    if (this.inputFieldsEnabled && !this.compactText(this.city)) {
      return this.setValidation(false, "city");
    }

    if (this.includeGeoLocation) {
      const hasPartialGeoLocation =
        Boolean(this.compactText(this.geoLocation?.lat)) !==
        Boolean(this.compactText(this.geoLocation?.lon));
      if (hasPartialGeoLocation) {
        return this.setValidation(false, "coordinates");
      }
    }

    this.args.field.value = this.buildLocationValue();
    return this.setValidation(true);
  }

  setValidation(valid, type) {
    const message = type ? i18n(`location.validation.${type}`) : "";
    this.args.field.setValid(valid, message);
    return valid;
  }

  @action
  setGeoLocation(gl) {
    const browserGeolocation = gl.source === BROWSER_GEOLOCATION_SOURCE;
    if (this.gpsLocked && !browserGeolocation) {
      return;
    }

    this.name = gl.name;
    this.street = gl.street;
    this.neighbourhood = gl.neighbourhood;
    this.postalcode = gl.postalcode;
    const resolvedState = resolvePrefectureName(
      gl.state ||
        gl.province ||
        gl.region ||
        gl.county ||
        this.extractJapanesePrefecture(gl.address)
    );
    const nextCity = String(gl.city || gl.district || "").trim();
    const nextState = String(resolvedState || "").trim();
    this.city = nextCity || this.city;
    this.state = nextState || this.state;
    this.geoLocation = {
      lat: this.compactText(gl.lat),
      lon: this.compactText(gl.lon),
    };
    this.countrycode = gl.countrycode || this.countrycode || "jp";
    this.rawLocation = gl.address || this.rawLocation || this.buildAreaAddress();
    this.lockRegionFields =
      !browserGeolocation && Boolean(nextState && nextCity);
    this.gpsLocked = browserGeolocation || this.isBrowserGeolocation(gl);
    this.gpsAccuracy = this.gpsLocked ? gl.accuracy : null;
    this.gpsCapturedAt = this.gpsLocked ? gl.captured_at : null;
    this.syncFieldValue();
  }

  @action
  onStateChange(value) {
    this.state = value;
    if (!this.lockRegionFields) {
      this.city = "";
    }
    this.syncFieldValue();
  }

  @action
  onCityChange(value) {
    this.city = value;
    this.syncFieldValue();
  }

  @action
  searchError(error) {
    this.flash = error;
  }

  <template>
    <LocationForm
      @street={{this.street}}
      @neighbourhood={{this.neighbourhood}}
      @postalcode={{this.postalcode}}
      @city={{this.city}}
      @state={{this.state}}
      @countrycode={{this.countrycode}}
      @geoLocation={{this.geoLocation}}
      @rawLocation={{this.rawLocation}}
      @inputFields={{this.inputFields}}
      @context={{this.context}}
      @useRegionSelectors={{true}}
      @stateOptions={{this.stateOptions}}
      @lockRegionFields={{this.lockRegionFields}}
      @coordinatesLocked={{this.gpsLocked}}
      @useBrowserGeolocation={{true}}
      @onStateChange={{this.onStateChange}}
      @onCityChange={{this.onCityChange}}
      @searchOnInit={{this.searchOnInit}}
      @setGeoLocation={{this.setGeoLocation}}
      @searchError={{this.searchError}}
      @geoAttrs={{array}}
      @showType={{true}}
    />
  </template>
}
