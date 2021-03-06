require 'google/apis/oauth2_v2'
require 'modules/auth'

class AuthController < ApplicationController
  rescue_from Signet::AuthorizationError do
    head :unauthorized
  end

  before_action :authenticate_user, only: [:restore]

  def new
    client = build_client
    redirect_to client.authorization_uri.to_s
  end

  def callback
    # apparently the only way to render a view in API-only mode without breaking everything
    html = ActionController::Base.new.render_to_string \
      'auth/callback',
      locals: {
        name: 'login',
        data: params.slice(:code)
      }
    render html: html
  end

  def sign_in
    client = build_client \
      code: params[:code]
    client.fetch_access_token!

    oauth2 = Google::Apis::Oauth2V2::Oauth2Service.new
    oauth2.authorization = client
    userinfo = oauth2.get_userinfo_v2

    # TODO don't allow registration
    # user = User.find_or_initialize_by(email: userinfo.email) do |new_user|
    #   new_user.authentication_token = SecureRandom.hex
    # end
    # user.save!
    user = User.find_by!(email: userinfo.email)

    render json: user,
           serializer: UserAuthSerializer
  end

  def restore
    render json: current_user,
           serializer: UserAuthSerializer
  end

  private
    def build_client(**options)
      Auth.build_client({
        redirect_uri: auth_callback_url,
        scope: ['email']
      }.merge(options))
    end
end
