package dns

import (
	"time"

	"github.com/tucowsinc/tdp-shared-go/dns"
	"github.com/tucowsinc/tdp-workers-go/pkg/config"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
)

// NewDNSResolver creates a new DNS resolver with the given configuration.
func NewDNSResolver(config config.Config) (resolver dns.IDnsResolver, err error) {
	var resolverOptions []dns.OptionsFunc
	if config.DNSCheckTimeout != 0 {
		var dnsTimeout = time.Duration(config.DNSCheckTimeout) * time.Second
		resolverOptions = append(resolverOptions, dns.WithTimeout(dnsTimeout))
	}
	if config.DNSResolverAddress != "" {
		resolverOptions = append(resolverOptions, dns.WithServer(config.DNSResolverAddress))
	}
	if config.DNSResolverPort != "" {
		resolverOptions = append(resolverOptions, dns.WithPort(config.DNSResolverPort))
	}
	if config.DNSResolverRecursion {
		resolverOptions = append(resolverOptions, dns.WithRecursion(config.DNSResolverRecursion))
	}

	resolver, err = dns.New(resolverOptions...)
	if err != nil {
		log.Error("Error creating new DNS resolver", log.Fields{"error": err})
		return
	}

	return
}
