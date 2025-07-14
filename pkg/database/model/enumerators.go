package model

import (
	"fmt"

	"gorm.io/gorm"
)

// Enumerate returns map of all items names to ids for job_status lookup table
func (*JobStatus) Enumerate(tx *gorm.DB) (data map[string]string, err error) {
	var items []JobStatus
	data = make(map[string]string)

	err = tx.Find(&items).Error
	if err != nil {
		return
	}

	for _, item := range items {
		data[item.Name] = item.ID
	}

	return

}

// Enumerate returns map of all items names to ids for job_type lookup table
func (*JobType) Enumerate(tx *gorm.DB) (data map[string]string, err error) {
	var items []JobType
	data = make(map[string]string)

	err = tx.Find(&items).Error
	if err != nil {
		return
	}

	for _, item := range items {
		data[item.Name] = item.ID
	}

	return

}

// Enumerate returns map of all items names to ids for provision_status lookup table
func (*ProvisionStatus) Enumerate(tx *gorm.DB) (data map[string]string, err error) {
	var items []ProvisionStatus
	data = make(map[string]string)

	err = tx.Find(&items).Error
	if err != nil {
		return
	}

	for _, item := range items {
		data[item.Name] = item.ID
	}

	return

}

// Enumerate returns map of all items names to ids for domain_contact_type lookup table
func (*DomainContactType) Enumerate(tx *gorm.DB) (data map[string]string, err error) {
	var items []DomainContactType
	data = make(map[string]string)

	err = tx.Find(&items).Error
	if err != nil {
		return
	}

	for _, item := range items {
		data[item.Name] = item.ID
	}

	return
}

// Enumerate returns map of all items names to ids for poll_message_type lookup table
func (*PollMessageType) Enumerate(tx *gorm.DB) (data map[string]string, err error) {
	var items []PollMessageType
	data = make(map[string]string)

	err = tx.Find(&items).Error
	if err != nil {
		return
	}

	for _, item := range items {
		data[item.Name] = item.ID
	}

	return
}

// Enumerate returns map of all items names to ids for poll_message_status lookup table
func (*PollMessageStatus) Enumerate(tx *gorm.DB) (data map[string]string, err error) {
	var items []PollMessageStatus
	data = make(map[string]string)

	err = tx.Find(&items).Error
	if err != nil {
		return
	}

	for _, item := range items {
		data[item.Name] = item.ID
	}

	return
}

// Enumerate returns map of all items names to ids for rgp_status lookup table
func (*RgpStatus) Enumerate(tx *gorm.DB) (data map[string]string, err error) {
	var items []RgpStatus
	data = make(map[string]string)

	err = tx.Find(&items).Error
	if err != nil {
		return
	}

	for _, item := range items {
		data[item.Name] = item.ID
	}

	return
}

// Enumerate returns map of all items names to ids for transfer_status lookup table
func (*TransferStatus) Enumerate(tx *gorm.DB) (data map[string]string, err error) {
	var items []TransferStatus
	data = make(map[string]string)

	err = tx.Find(&items).Error
	if err != nil {
		return
	}

	for _, item := range items {
		data[item.Name] = item.ID
	}

	return
}

// Enumerate returns map of all items names to ids for order_item_plan_status lookup table
func (*OrderItemPlanStatus) Enumerate(tx *gorm.DB) (data map[string]string, err error) {
	var items []OrderItemPlanStatus
	data = make(map[string]string)

	err = tx.Find(&items).Error
	if err != nil {
		return
	}

	for _, item := range items {
		data[item.Name] = item.ID
	}

	return
}

// Enumerate returns map of all items names to ids for order_item_plan_status lookup table
func (*OrderItemPlanValidationStatus) Enumerate(tx *gorm.DB) (data map[string]string, err error) {
	var items []OrderItemPlanValidationStatus
	data = make(map[string]string)

	err = tx.Find(&items).Error
	if err != nil {
		return
	}

	for _, item := range items {
		data[item.Name] = item.ID
	}

	return
}

// Enumerate returns map of all items names to ids for v_order_type lookup view
func (*VOrderType) Enumerate(tx *gorm.DB) (data map[string]string, err error) {
	var items []VOrderType
	data = make(map[string]string)

	err = tx.Find(&items).Error
	if err != nil {
		return
	}

	for _, item := range items {
		data[fmt.Sprintf("%v.%v", *item.Name, *item.ProductName)] = *item.ID
	}

	return
}

// Enumerate returns map of all items names to ids for order_status lookup table
func (*HostingStatus) Enumerate(tx *gorm.DB) (data map[string]string, err error) {
	var items []HostingStatus
	data = make(map[string]string)

	err = tx.Find(&items).Error
	if err != nil {
		return
	}

	for _, item := range items {
		data[item.Name] = item.ID
	}

	return
}
