package types

type DNSCheckData struct {
	DomainName string   `json:"domain_name"`
	Metadata   Metadata `json:"order_metadata"`
}

type HostingData struct {
	DomainName       string              `json:"domain_name"`
	ProductId        string              `json:"product_id"`
	RegionId         string              `json:"region_id"`
	Components       []HostingComponent  `json:"components"`
	Client           HostingClient       `json:"client"`
	Certificate      *HostingCertificate `json:"certificate"`
	CustomerName     string              `json:"customer_name"`
	CustomerEmail    string              `json:"customer_email"`
	TenantCustomerId string              `json:"tenant_customer_id"`
	HostingId        string              `json:"hosting_id"`
	Metadata         Metadata            `json:"metadata"`
}

type HostingUpdateData struct {
	HostingId       string              `json:"hosting_id"`
	ExternalOrderId string              `json:"external_order_id"`
	IsActive        *bool               `json:"is_active"`
	Certificate     *HostingCertificate `json:"certificate"`
	Metadata        Metadata            `json:"metadata"`
}

type HostingClient struct {
	ExternalClientId *string `json:"external_client_id"`
	Name             string  `json:"name"`
	Email            string  `json:"email"`
	Username         string  `json:"username"`
	Password         string  `json:"password"`
}

type HostingComponent struct {
	Name string `json:"name"`
	Type string `json:"type"`
}

type HostingCertificate struct {
	Body       string `json:"body"`
	Chain      string `json:"chain"`
	PrivateKey string `json:"private_key"`
}

// from reading online fullchain is just cert + chain (in our case we're calling cert body)
// storing this is pointless, we can just construct it if needed
type HostingCertificateData struct {
	DomainName string `json:"domain_name"`
	// this will be the hosting id from the db, we can use this
	// to associate the certbot response with the correct hosting record
	RequestId string `json:"request_id"`
	HostingCertificate
	Metadata Metadata `json:"order_metadata"`
}

type HostingDeleteData struct {
	HostingId       string   `json:"hosting_id"`
	ExternalOrderId string   `json:"external_order_id"`
	Metadata        Metadata `json:"metadata"`
}
