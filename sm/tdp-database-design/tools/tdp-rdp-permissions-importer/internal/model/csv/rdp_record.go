package modelcsv

type RDPRecord struct {
	ContactType                       string `csv:"Object"`
	DataElementName                   string `csv:"Database element name"`
	DataElementPath                   string `csv:"DB data element path"`
	Collection                        string `csv:"collection"`
	TransmissionRegistry              string `csv:"transmission (registry)"`
	TransmissionEscrow                string `csv:"transmission (escrow)"`
	DefaultPublication                string `csv:"publish_by_default"`
	AvailableForConsent               string `csv:"available_for_consent"`
	CollectionStartValidity           string `csv:"collection start validity date"`
	TransmissionRegistryStartValidity string `csv:"transmission registry start validity date"`
	TransmissionEscrowStartValidity   string `csv:"escrow start validity date"`
}
