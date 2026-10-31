require "rails_helper"

RSpec.describe "Health check", type: :request do
  it "responds with 200 on GET /up" do
    get "/up"

    expect(response).to have_http_status(200)
  end

  it "responds with 404 on an undefined route" do
    get "/undefined-route"

    expect(response).to have_http_status(404)
  end
end
