#!/bin/bash

ca_running() {
  status=$(curl --silent --fail --insecure "https://${CA_HOSTNAME}:${CA_MASTERPORT}/status/v1/simple")
  test "$status" = "running"
}

hocon() {
  /opt/puppetlabs/puppet/lib/ruby/vendor_gems/bin/hocon "$@"
}

CA_HOSTNAME="${CA_HOSTNAME:-puppet}"
CA_MASTERPORT="${CA_MASTERPORT:-8140}"

if [[ "$CA_ENABLED" != "true" ]]; then
  # we are just an ordinary compiler
  echo "turning off CA"
  cat > /etc/puppetlabs/puppetserver/services.d/ca.cfg <<EOF
puppetlabs.services.ca.certificate-authority-disabled-service/certificate-authority-disabled-service
puppetlabs.trapperkeeper.services.watcher.filesystem-watch-service/filesystem-watch-service
EOF

  ssl_cert=$(puppet config print hostcert)
  ssl_key=$(puppet config print hostprivkey)
  ssl_ca_cert=$(puppet config print localcacert)
  ssl_crl_path=$(puppet config print hostcrl)


  cd /etc/puppetlabs/puppetserver/conf.d/
  hocon -f webserver.conf set webserver.ssl-cert $ssl_cert
  hocon -f webserver.conf set webserver.ssl-key $ssl_key
  hocon -f webserver.conf set webserver.ssl-ca-cert $ssl_ca_cert
  hocon -f webserver.conf set webserver.ssl-crl-path $ssl_crl_path
  cd /

  # bootstrap certs for the puppetserver
  if [[ ! -f "$ssl_cert" ]]; then
    while ! ca_running; do
      sleep 1
    done

    puppet ssl bootstrap --server="${CA_HOSTNAME}" --masterport="${CA_MASTERPORT}"
  fi
else
  # we are the CA
  hocon -f /etc/puppetlabs/puppetserver/conf.d/ca.conf \
    set certificate-authority.allow-subject-alt-names "${CA_ALLOW_SUBJECT_ALT_NAMES}"

  # Generate the same SSL directory that the PE installer creates.
  #
  # The steps in this file correspond to the steps in the PE installer.
  #
  # See https://github.com/puppetlabs/puppet-enterprise-modules/blob/kearney/modules/pe_install/manifests/prepare/certificates.pp

  if [ ! -d "$SSLDIR" ] || [ ! "$(ls -A "$SSLDIR")" ]; then
      # Append user-supplied DNS Alt Names
      if [ -n "$DNS_ALT_NAMES" ]; then
          current="$(puppet config print --section main dns_alt_names)"
          puppet config set --section main dns_alt_names "$current","$DNS_ALT_NAMES"
      fi

      timestamp="$(date '+%Y-%m-%d %H:%M:%S %z')"
      ca_name="Puppet Enterprise CA generated on ${HOSTNAME} at $timestamp"

      # See puppet.conf file for relevant settings
      puppetserver ca setup \
          --ca-name "$ca_name" \
          --config /etc/puppetlabs/puppet/puppet.conf
  fi
fi
