import Component from "@glimmer/component";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import didUpdate from "@ember/render-modifiers/modifiers/did-update";
import { service } from "@ember/service";
import AddLocationControls from "../../components/add-location-controls";

export default class ComposerControlsLocation extends Component {
  @service site;

  /**
   * Returns the active composer model.
   *
   * @returns {object} Active composer model.
   */
  get model() {
    return this.args.outletArgs.model;
  }

  /**
   * Updates the tracked composer location.
   *
   * @param {object|null} location New location value.
   * @returns {void}
   */
  @action
  updateLocation(location) {
    this.model.location = location;
  }

  /**
   * Sets up the default after draft, category, or user-location changes.
   *
   * @returns {void}
   */
  @action
  setupDefaultLocation() {
    this.model.maybeSetupDefaultLocation?.();
  }

  <template>
    <div
      {{didInsert this.setupDefaultLocation}}
      {{didUpdate
        this.setupDefaultLocation
        this.model.draftKey
        this.model.categoryId
        this.model.showLocationControls
        this.model.user.geo_location
        this.model.user.custom_fields.geo_location
      }}
    >
      {{#if this.model.showLocationControls}}
        <AddLocationControls
          @location={{this.model.location}}
          @category={{this.model.category}}
          @noText={{this.site.mobileView}}
          @updateLocation={{this.updateLocation}}
        />
      {{/if}}
    </div>
  </template>
}
