require 'rails_helper'

RSpec.describe "Pages", type: :request do

  # Uncomment this if controller need authentication
  # let(:user) { last_or_create(:user) }
  # before { sign_in_as(user) }

  describe "GET /pages/features" do
    it "returns http success" do
      get features_pages_path
      expect(response).to be_success_with_view_check('features')
    end
  end


  describe "GET /pages/about" do
    it "returns http success" do
      get about_pages_path
      expect(response).to be_success_with_view_check('about')
    end
  end


  describe "GET /pages/contact" do
    it "returns http success" do
      get contact_pages_path
      expect(response).to be_success_with_view_check('contact')
    end
  end

end
