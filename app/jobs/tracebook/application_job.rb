module Tracebook
  class ApplicationJob < ActiveJob::Base
    queue_as :tracebook
  end
end
