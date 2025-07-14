package certificate

import (
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"time"

	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

// ParseCertificates parses PEM-encoded certificates and returns a slice of *x509.Certificate.
func ParseCertificates(pemCerts []byte) ([]*x509.Certificate, error) {
	var certificates []*x509.Certificate
	for {
		block, rest := pem.Decode(pemCerts)
		if block == nil {
			break
		}

		if block.Type != "CERTIFICATE" {
			return nil, fmt.Errorf("only CERTIFICATE PEM blocks are allowed, found %q", block.Type)
		}
		if len(block.Headers) != 0 {
			return nil, fmt.Errorf("no PEM block headers are permitted")
		}

		certs, err := x509.ParseCertificates(block.Bytes)
		if err != nil {
			return nil, err
		}
		if len(certs) == 0 {
			return nil, fmt.Errorf("found CERTIFICATE PEM block containing 0 valid certificates")
		}

		certificates = append(certificates, certs...)
		pemCerts = rest
	}
	if len(certificates) == 0 {
		return nil, fmt.Errorf("unable to parse certificate")
	}

	return certificates, nil
}

// ParseSingleCertificates parses PEM-encoded certificate to *x509.Certificate.
func ParseSingleCertificates(pemCerts []byte) (*x509.Certificate, error) {
	certificates, err := ParseCertificates(pemCerts)
	if err != nil {
		return nil, err
	}

	if len(certificates) != 1 {
		return nil, fmt.Errorf("CERTIFICATE body must contain one CERTIFICATE")
	}

	return certificates[0], nil
}

func GetCertificateValidDates(certBody string) (notBefore *time.Time, notAfter *time.Time) {
	cert, err := ParseSingleCertificates([]byte(certBody))
	if err != nil {
		log.Debug("invalid cert", log.Fields{
			types.LogFieldKeys.Error: err.Error(),
		})
		return
	}
	notBefore = &cert.NotBefore
	notAfter = &cert.NotAfter

	return
}
