# frozen_string_literal: true
require "rails_helper"

RSpec.describe "Locations.normalize_topic_location" do
  it "normalizes browser geolocation metadata and locks GPS coordinates" do
    location =
      Locations.normalize_topic_location(
        {
          "state" => "Tokyo",
          "city" => "Shinjuku",
          "source" => "browser_geolocation",
          "precision" => "gps",
          "gps_locked" => "true",
          "accuracy" => "12.5",
          "captured_at" => "2026-05-25T12:00:00.000Z",
          "geo_location" => {
            "lat" => 35.6895,
            "lon" => 139.6917,
          },
        },
      )

    expect(location).to include(
      "state" => "Tokyo",
      "city" => "Shinjuku",
      "source" => "browser_geolocation",
      "precision" => "exact",
      "gps_locked" => true,
      "accuracy" => 12.5,
      "captured_at" => "2026-05-25T12:00:00.000Z",
      "geo_location" => {
        "lat" => "35.6895",
        "lon" => "139.6917",
      },
    )
  end

  it "rejects GPS locked locations without valid coordinates" do
    expect {
      Locations.normalize_topic_location(
        {
          "source" => "browser_geolocation",
          "precision" => "gps",
          "gps_locked" => true,
          "geo_location" => {
            "lat" => "91",
            "lon" => "139.6917",
          },
        },
      )
    }.to raise_error(Discourse::InvalidParameters)
  end

  it "keeps area locations without coordinates publishable" do
    location =
      Locations.normalize_topic_location(
        {
          "state" => "Tokyo",
          "city" => "Shinjuku",
          "countrycode" => "jp",
          "address" => "Tokyo Shinjuku",
          "precision" => "area",
        },
      )

    expect(location).to eq(
      {
        "state" => "Tokyo",
        "city" => "Shinjuku",
        "countrycode" => "jp",
        "address" => "Tokyo Shinjuku",
        "precision" => "area",
      },
    )
  end
end
