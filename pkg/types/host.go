package types

type HostData struct {
	HostId                string           `json:"host_id"`
	HostName              string           `json:"host_name"`
	HostAddrs             []string         `json:"host_addrs"`
	Accreditation         Accreditation    `json:"accreditation"`
	HostAccreditationTld  AccreditationTld `json:"host_accreditation_tld"`
	HostIpRequiredNonAuth bool             `json:"host_ip_required_non_auth"`
	ProvisionHostId       string           `json:"provision_host_id"`
	TenantCustomerId      string           `json:"tenant_customer_id"`
}

type HostUpdateData struct {
	HostId                string        `json:"host_id"`
	HostName              string        `json:"host_name"`
	HostNewAddrs          []string      `json:"host_new_addrs"`
	HostOldAddrs          []string      `json:"host_old_addrs"`
	Accreditation         Accreditation `json:"accreditation"`
	ProvisionHostUpdateId string        `json:"provision_host_update_id"`
	TenantCustomerId      string        `json:"tenant_customer_id"`
}

type HostValidationData struct {
	HostName         string        `json:"host_name"`
	OrderItemPlanId  string        `json:"order_item_plan_id"`
	Accreditation    Accreditation `json:"accreditation"`
	TenantCustomerId string        `json:"tenant_customer_id"`
}

type HostDeleteData struct {
	HostId                  string        `json:"host_id"`
	HostName                string        `json:"host_name"`
	HostDeleteRenameAllowed bool          `json:"host_delete_rename_allowed"`
	HostDeleteRenameDomain  string        `json:"host_delete_rename_domain"`
	Accreditation           Accreditation `json:"accreditation"`
	ProvisionHostDeleteId   *string       `json:"provision_host_delete_id"`
	ProvisionDomainDeleteId *string       `json:"provision_domain_delete_id"`
	TenantCustomerId        string        `json:"tenant_customer_id"`
}
