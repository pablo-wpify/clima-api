require "rails_helper"

# Temporary spec for verification V22 (add-rails-api-base): it fails on purpose
# to check that a failing example makes the GitHub Actions `test` job fail.
# This branch is never merged.
RSpec.describe "V22 deliberate failure" do
  it "fails on purpose" do
    expect(1 + 1).to eq(3)
  end
end
