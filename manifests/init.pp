class gnupg {
    class base {
	$keymaster_storage = "/var/lib/gpgkeys"

	$pubkey_storage = "/var/lib/gpg-pubkeys"
	$privkey_storage = "/var/lib/gpg-privkeys"

	file {[ $pubkey_storage, $privkey_storage ]:
	    ensure => directory,
	    owner => root,
	    group => root,
	    mode => 711,
	}

        package { ["gnupg","rng-tools"]:
            ensure => present,
        }
        
        file { "/usr/local/bin/create_gnupg_keys.sh":
             ensure => present,
             owner => root,
             group => root,
             mode => 755,
             content => template('gnupg/create_gnupg_keys.sh')
        }
    }

    class keymaster {
	include base
	file { $gnupg::base::keymaster_storage:
	    ensure => directory,
	    owner => root,
	    group => root,
	}

	Gnupg::Gnupg_key_master <| |>
    }

    define pubkey($keydir, $user) {
	Gnupg::Gnupg_pubkey <| title == $title |> {
	    keydir => $keydir,
	    user => $user,
	}
    }

    define privkey($keydir, $user) {
	Gnupg::Gnupg_privkey <| title == $title |> {
	    keydir => $keydir,
	    user => $user,
	}
    }

    define gnupg_key($email, $key_name, $expire_date = '400d') {
	include base
	@gnupg_key_master { $name:
	    email => $email,
	    key_name => $key_name,
	    expire_date => $expire_date,
	}
	@gnupg::gnupg_pubkey { $name:
	}
	@gnupg::gnupg_privkey { $name:
	}
    }

    define gnupg_key_master($email, $key_name, $expire_date = '400d') {
	include base
	$basedir = "$base::keymaster_storage/$name"
	$keydir = "$base::keymaster_storage/$name/keydir"
	$batchdir = "$base::keymaster_storage/$name/batches"

	$privkey = "$base::keymaster_storage/$name/privkey"
	$pubkey = "$base::keymaster_storage/$name/pubkey"
	$keyid = "$base::keymaster_storage/$name/keyid"

	file { [ $basedir, $keydir, $batchdir ]:
	    ensure => directory,
	    owner => puppet,
	    group => root,
	    mode => 700,
	}

	gnupg::keys{$name:
	    email => $email,
	    key_name => $key_name,
	    keydir => $keydir,
	    batchdir => $batchdir,
	    expire_date => $expire_date,
	    require => [File[$keydir], File[$batchdir]],
	}

	exec {"gpg --homedir \"$keydir\" --list-keys | grep '^pub' | sed 's:^pub\s\\+.\\+/::;s/ .*$//' > $keyid":
	    creates => $keyid,
	    require => Gnupg::Keys[$name],
	}

	exec {"gpg --homedir \"$keydir\" --export -a > $pubkey":
	    creates => $pubkey,
	    require => Gnupg::Keys[$name],
	}

	exec {"gpg --homedir \"$keydir\" --export-secret-keys -a > $privkey":
	    creates => $privkey,
	    require => Gnupg::Keys[$name],
	}
    }

    define gnupg_pubkey($keydir, $user) {
	include base
	$pubkey = "$base::keymaster_storage/$name/pubkey"
	$keyidfile = "${gnupg::base::keymaster_storage}/$name/keyid"
	$keyid = file($keyidfile, '/dev/null')

	if $keyid != '' {
	    file { "$base::pubkey_storage/$name":
		ensure => present,
		content => file($pubkey),
		owner => $user,
		mode => 600,
	    }
	    exec { "gpg --homedir \"$keydir\" --import \"$base::pubkey_storage/$name\"":
		user => $user,
		unless => "gpg --homedir \"$keydir\" --list-keys \"$keyid\" > /dev/null 2>&1",
		require => File["$base::pubkey_storage/$name"],
	    }
	} else {
	    notify { "Private key $name not found on keymaster - keyid: $keyid $keyidfile": }
	}
    }

    define gnupg_privkey($keydir, $user) {
	include base
	$privkey = "$gnupg::base::keymaster_storage/$name/privkey"
	$keyid = file("$gnupg::base::keymaster_storage/$name/keyid", '/dev/null')

	if $keyid != '' {
	    file { "$base::privkey_storage/$name":
		ensure => present,
		content => file($privkey),
		owner => $user,
		mode => 600,
	    }
	    exec { "gpg --homedir \"$keydir\" --import \"$base::privkey_storage/$name\"":
		user => $user,
		unless => "gpg --homedir \"$keydir\" --list-secret-keys \"$keyid\" > /dev/null 2>&1",
		require => File["$base::privkey_storage/$name"],
	    }
	}
    }

    # debian recommend SHA2, with 4096
    # http://wiki.debian.org/Keysigning
    # as they are heavy users of gpg, I will tend 
    # to follow them
    # however, for testing purpose, 4096 is too strong, 
    # this empty the entropy of my vm
    define keys( $email,
                 $key_name,
                 $key_type = 'RSA',
                 $key_length = '4096',
                 $expire_date = '400d',
		 $login = 'root',
		 $batchdir = '/var/lib/signbot/batches',
		 $keydir = '/var/lib/signbot/keys'
                 ) {

            include gnupg::base
            file { "$name.batch":
                ensure => present,
                path => "$batchdir/$name.batch",
                content => template("gnupg/batch")
            }

            exec { "/usr/local/bin/create_gnupg_keys.sh $batchdir/$name.batch $keydir $batchdir/$name.done":
                 user => $login,
                 creates => "$batchdir/$name.done",
                 require => [File["$keydir"], File["$batchdir/$name.batch"], Package["rng-tools"]],
            }
    }
}
