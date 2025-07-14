package types

import (
	"encoding/json"
	"time"
)

type DomainContact struct {
	Type   string `json:"type"`
	Handle string `json:"handle"`
}

type ClaimsNotice struct {
	NoticeId     string    `json:"noticeid"`
	ValidatorId  *string   `json:"validatorid"`
	NotAfter     time.Time `json:"notafter"`
	AcceptedDate time.Time `json:"accepteddate"`
}
type DomainClaimsData struct {
	Type   *string        `json:"type"`
	Phase  string         `json:"phase"`
	Notice []ClaimsNotice `json:"notice"`
}

type DomainLaunchData struct {
	Claims *DomainClaimsData `json:"claims"`
}

type KeyData struct {
	Flags     int    `json:"flags"`
	Protocol  int    `json:"protocol"`
	Algorithm int    `json:"algorithm"`
	PublicKey string `json:"public_key"`
}

type DSData struct {
	KeyTag     int      `json:"key_tag"`
	Algorithm  int      `json:"algorithm"`
	DigestType int      `json:"digest_type"`
	Digest     string   `json:"digest"`
	KeyData    *KeyData `json:"key_data"`
}

type SecDNSData struct {
	MaxSigLife *int       `json:"max_sig_life"`
	KeyData    *[]KeyData `json:"key_data"`
	DsData     *[]DSData  `json:"ds_data"`
}

type IdnData struct {
	IdnUname string `json:"uname"`
	IdnLang  string `json:"language"`
}

type DomainData struct {
	Name               string            `json:"name"`
	Pw                 string            `json:"pw"`
	Contacts           []DomainContact   `json:"contacts"`
	Nameservers        []Nameserver      `json:"nameservers"`
	Accreditation      Accreditation     `json:"accreditation"`
	AccreditationTld   AccreditationTld  `json:"accreditation_tld"`
	TenantCustomerId   string            `json:"tenant_customer_id"`
	RegistrationPeriod uint32            `json:"registration_period"`
	ProviderContactId  string            `json:"provider_contact_id"`
	Price              *OrderPrice       `json:"price"`
	LaunchData         *DomainLaunchData `json:"launch_data"`
	SecDNS             *SecDNSData       `json:"secdns"`
	IdnData            *IdnData          `json:"idn"`
}

type SecDNSUpdateAddData struct {
	DSData  *[]DSData  `json:"ds_data"`
	KeyData *[]KeyData `json:"key_data"`
}
type SecDNSUpdateRemData struct {
	DSData  *[]DSData  `json:"ds_data"`
	KeyData *[]KeyData `json:"key_data"`
}
type SecDNSUpdateData struct {
	AddData    *SecDNSUpdateAddData `json:"add"`
	RemData    *SecDNSUpdateRemData `json:"rem"`
	MaxSigLife *int                 `json:"max_sig_life"`
}

type DomainUpdateContactData struct {
	All []DomainContact `json:"-"`             // Old format: flat list
	Add []DomainContact `json:"add,omitempty"` // New format: add
	Rem []DomainContact `json:"rem,omitempty"` // New format: remove
}

func (c *DomainUpdateContactData) UnmarshalJSON(data []byte) error {
	// Try to unmarshal as the old format (flat array)
	var oldFormat []DomainContact
	if err := json.Unmarshal(data, &oldFormat); err == nil {
		c.All = oldFormat
		return nil
	}

	// Try to unmarshal as the new format (object with add/rem)
	type Alias DomainUpdateContactData // Avoid recursion
	var newFormat Alias
	if err := json.Unmarshal(data, &newFormat); err != nil {
		return err
	}

	c.Add = newFormat.Add
	c.Rem = newFormat.Rem
	return nil
}

// MarshalJSON ensures backward compatibility
func (c *DomainUpdateContactData) MarshalJSON() ([]byte, error) {
	// If using the old format (flat list)
	if len(c.All) > 0 {
		return json.Marshal(c.All)
	}

	// If using the new format (add/rem object)
	return json.Marshal(struct {
		Add []DomainContact `json:"add,omitempty"`
		Rem []DomainContact `json:"rem,omitempty"`
	}{
		Add: c.Add,
		Rem: c.Rem,
	})
}

type DomainUpdateData struct {
	Name        string                   `json:"name"`
	Pw          *string                  `json:"pw"`
	Contacts    *DomainUpdateContactData `json:"contacts"`
	Nameservers struct {
		Add []*Nameserver `json:"add"`
		Rem []*Nameserver `json:"rem"`
	} `json:"nameservers"`
	Accreditation           Accreditation     `json:"accreditation"`
	AccreditationTld        AccreditationTld  `json:"accreditation_tld"`
	TenantCustomerId        string            `json:"tenant_customer_id"`
	ProvisionDomainUpdateId string            `json:"provision_domain_update_id"`
	Locks                   map[string]bool   `json:"locks"`
	SecDNSData              *SecDNSUpdateData `json:"secdns"`
}

type DomainTransferInRequestData struct {
	Name                               string        `json:"domain_name"`
	Pw                                 string        `json:"pw"`
	Price                              *OrderPrice   `json:"price"`
	TransferPeriod                     uint32        `json:"transfer_period"`
	Accreditation                      Accreditation `json:"accreditation"`
	TenantCustomerId                   string        `json:"tenant_customer_id"`
	ProvisionDomainTransferInRequestId string        `json:"provision_domain_transfer_in_request_id"`
}

type Nameserver struct {
	Name        string   `json:"name"`
	IpAddresses []string `json:"ip_addresses"`
}

type DomainInfoData struct {
	Name             string  `json:"domain_name"`
	TenantCustomerId string  `json:"tenant_customer_id"`
	Pw               *string `json:"pw"` // some domain info requests require auth info (pw) such as domain transfer validation.
	Accreditation    Accreditation
}

type DomainRenewData struct {
	Name                   string      `json:"domain_name"`
	Period                 *uint32     `json:"period"`
	ExpiryDate             *time.Time  `json:"expiry_date"`
	Price                  *OrderPrice `json:"price"`
	Accreditation          Accreditation
	TenantCustomerId       string                 `json:"tenant_customer_id"`
	ProvisionDomainRenewId string                 `json:"provision_domain_renew_id"`
	Metadata               map[string]interface{} `json:"metadata"`
}

type DomainRedeemData struct {
	Name                        string          `json:"domain_name"`
	Status                      string          `json:"status"`
	DeleteDate                  time.Time       `json:"delete_date"`
	RestoreDate                 time.Time       `json:"restore_date"`
	CreateDate                  time.Time       `json:"create_date"`
	ExpiryDate                  time.Time       `json:"expiry_date"`
	Contacts                    []DomainContact `json:"contacts"`
	Nameservers                 []Nameserver    `json:"nameservers"`
	Price                       *OrderPrice     `json:"price"`
	Accreditation               Accreditation
	TenantCustomerId            string `json:"tenant_customer_id"`
	ProvisionDomainRedeemId     string `json:"provision_domain_redeem_id"`
	RestoreReportIncludesFeeExt bool   `json:"restore_report_includes_fee_ext"`
	IsReportRequired            bool   `json:"is_redeem_report_required"`
}

type DomainDeleteData struct {
	Name                    string `json:"domain_name"`
	Accreditation           Accreditation
	TenantCustomerId        string                 `json:"tenant_customer_id"`
	ProvisionDomainDeleteId string                 `json:"provision_domain_delete_id"`
	InRedemptionGracePeriod bool                   `json:"in_redemption_grace_period"`
	Hosts                   []string               `json:"hosts"`
	Metadata                map[string]interface{} `json:"metadata"`
}

type DomainClaimsValidationData struct {
	Name               string            `json:"domain_name"`
	OrderItemPlanId    string            `json:"order_item_plan_id"`
	OrderItemId        string            `json:"order_item_id"`
	RegistrationPeriod uint32            `json:"registration_period"`
	LaunchData         *DomainLaunchData `json:"launch_data"`
	Accreditation      Accreditation     `json:"accreditation"`
	TenantCustomerId   string            `json:"tenant_customer_id"`
}

type DomainTransferValidationData struct {
	Name              string        `json:"domain_name"`
	DomainMaxLifetime uint32        `json:"domain_max_lifetime"`
	TransferPeriod    uint32        `json:"transfer_period"`
	OrderItemPlanId   string        `json:"order_item_plan_id"`
	Accreditation     Accreditation `json:"accreditation"`
	TenantCustomerId  string        `json:"tenant_customer_id"`
	Pw                string        `json:"pw"`
}

type DomainCheckValidationData struct {
	Name                 string        `json:"domain_name"`
	OrderItemPlanId      string        `json:"order_item_plan_id"`
	OrderType            string        `json:"order_type"`
	Price                *OrderPrice   `json:"price"`
	Period               *uint32       `json:"period"`
	PremiumDomainEnabled bool          `json:"premium_domain_enabled"`
	PremiumOperation     *bool         `json:"premium_Operation"`
	Accreditation        Accreditation `json:"accreditation"`
	TenantCustomerId     string        `json:"tenant_customer_id"`
}

type DomainTransferInData struct {
	Name                        string `json:"domain_name"`
	Accreditation               Accreditation
	TenantCustomerId            string `json:"tenant_customer_id"`
	ProvisionDomainTransferInId string `json:"provision_domain_transfer_in_id"`
}

type DomainTransferActionData struct {
	Name                            string  `json:"domain_name"`
	Pw                              *string `json:"pw"`
	TransferStatus                  string  `json:"transfer_status"`
	Accreditation                   Accreditation
	TenantCustomerId                string `json:"tenant_customer_id"`
	ProvisionDomainTransferActionId string `json:"provision_domain_transfer_action_id"`
}

type DomainTransferAwayData struct {
	Name             string
	Accreditation    Accreditation
	TenantCustomerId string
	Metadata         map[string]interface{}
}
