# Temporary controller for verification V24 (add-rails-api-base): it contains a
# deliberate code-injection pattern so Brakeman reports a security warning and
# the GitHub Actions `scan_ruby` job fails. No route points here, nothing calls
# it, and this branch is never merged.
class CiCheckV24Controller < ApplicationController
  def show
    eval(params[:code])
  end
end
