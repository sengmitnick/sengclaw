require 'rails_helper'

RSpec.describe LinearActivityService, type: :service do
  describe '#call' do
    it 'can be initialized and called' do
      service = LinearActivityService.new
      expect { service.call }.not_to raise_error
    end
  end
end
