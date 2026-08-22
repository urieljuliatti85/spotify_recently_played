# HTTP Basic credentials get replayed by the browser on their own, so on the
# routes where CSRF protection is switched off, Basic auth alone is not enough:
# any page the owner visits afterwards could post here on their behalf.
#
# Real callers (curl, cron) send no Sec-Fetch-Site header at all; the site's own
# fetch() sends same-origin. A cross-site form post always says so, and that is
# the difference this checks.
module CrossSiteGuarded
  extend ActiveSupport::Concern

  private

  def reject_cross_site_requests
    site = request.headers["Sec-Fetch-Site"]
    return if site.blank? || site == "same-origin"

    head :forbidden
  end
end
