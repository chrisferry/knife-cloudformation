require 'knife-cloudformation/cloudformation_base'
require File.join(File.dirname(__FILE__), 'cloudformation_create')

class Chef
  class Knife
    class CloudformationUpdate < Knife
      banner 'knife cloudformation update NAME'

      include KnifeCloudformation::KnifeBase
      include CloudformationCreate::Options

      def run
        create_or_update_run(:update)
      end

    end
  end
end
