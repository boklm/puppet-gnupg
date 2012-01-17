module Puppet::Parser::Functions
    newfunction(:gnupg_keyid, :type => :rvalue) do |args|
	keyname = args[0]

	keymaster_storage = lookupvar('gnupg::base::keymaster_storage')
	keyidfile = keymaster_storage + '/' + keyname + '/keyid'
	Puppet::Parser::Functions.autoloader.loadall
	return function_file([keyidfile, '/dev/null'])
    end
end
