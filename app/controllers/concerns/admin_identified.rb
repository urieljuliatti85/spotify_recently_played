# Whether the caller already holds the owner's credentials — asked without
# challenging for them.
#
# AdminAuthenticated turns the same answer into a 401, which is right for a
# route only the owner is meant to reach. The public feed needs the question
# asked more quietly: it decides whether to *offer* an owner-only action at
# all, and popping a Basic auth dialog at every visitor to find that out would
# be absurd.
module AdminIdentified
  extend ActiveSupport::Concern

  private

  def admin_password
    ENV["ADMIN_PASSWORD"].presence
  end

  # Deliberately not `authenticate_with_http_basic`: ActionController::API does
  # not carry that helper, and this has to answer the same way for the JSON
  # status endpoint and for the HTML owner routes.
  def admin?
    return Rails.env.development? && request.local? if admin_password.nil?

    given = ActionController::HttpAuthentication::Basic
      .decode_credentials(request).to_s.split(":", 2).last.to_s
    return false if given.blank?

    ActiveSupport::SecurityUtils.secure_compare(given, admin_password)
  end
end
