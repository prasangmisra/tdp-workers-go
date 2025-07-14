package handlers

import (
	"context"
	"encoding/json"

	"github.com/google/uuid"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/anypb"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	commonmessages "github.com/tucowsinc/tdp-messages-go/message/common"
	"github.com/tucowsinc/tdp-messages-go/message/job"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	rymessages "github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface/extension"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

var RYContactTypeMap = map[string]commonmessages.DomainContact_DomainContactType{
	"admin":   commonmessages.DomainContact_ADMIN,
	"billing": commonmessages.DomainContact_BILLING,
	"tech":    commonmessages.DomainContact_TECH,
}

// DomainUpdateHandler This is a callback handler for the DomainProvision event
// and is in charge of sending the request to the registry interface
func (service *WorkerService) DomainUpdateHandler(server messagebus.Server, message proto.Message) error {
	ctx := server.Context()
	headers := server.Headers()
	span, ctx := service.tracer.CreateSpanFromHeaders(ctx, headers, "DomainUpdateHandler")
	defer service.tracer.FinishSpan(span)

	// we need to type-cast the proto.Message to the wanted type
	request := message.(*job.Notification)
	jobId := request.GetJobId()

	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.CorrelationID: jobId,
	})

	logger.Debug("Starting DomainUpdateHandler for the job")

	data := new(types.DomainUpdateData)

	return service.db.WithTransaction(func(tx database.Database) (err error) {
		job, err := tx.GetJobById(ctx, jobId, true)
		if err != nil {
			logger.Error(types.LogMessages.FetchJobByIDFromDBFailed, log.Fields{types.LogFieldKeys.Error: err})
			return
		}

		logger = logger.CreateChildLogger(log.Fields{
			types.LogFieldKeys.LogID:   uuid.NewString(),
			types.LogFieldKeys.JobType: *job.Info.JobTypeName,
		})

		logger.Info("Starting domain update job processing")

		if job.StatusID != tx.GetJobStatusId(types.JobStatus.Submitted) {
			logger.Warn(types.LogMessages.UnexpectedJobStatus, log.Fields{
				types.LogFieldKeys.Status: job.Info.JobStatusName,
			})
			return
		}

		err = json.Unmarshal(job.Info.Data, data)
		if err != nil {
			logger.Error(types.LogMessages.JSONDecodeFailed, log.Fields{
				types.LogFieldKeys.Error: err,
			})

			resMsg := err.Error()
			job.ResultMessage = &resMsg
			err = tx.SetJobStatus(ctx, job, types.JobStatus.Failed, nil)
			if err != nil {
				logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
					types.LogFieldKeys.Error: err,
				})
			}
			return
		}

		logger.Info("Validated job data for domain update")

		// check if the registry supports host objects
		hostObjectSupported, err := getBoolAttribute(tx, ctx, "tld.order.host_object_supported", data.AccreditationTld.AccreditationTldId)
		if err != nil {
			logger.Error("Failed to fetch host object support attribute", log.Fields{types.LogFieldKeys.Error: err})
			return err
		}

		msg, err := toDomainUpdateRequest(ctx, service, tx, *data, types.SafeDeref(hostObjectSupported))
		if err != nil {
			logger.Error(types.LogMessages.ParseJobDataToRegistryRequestFailed, log.Fields{types.LogFieldKeys.Error: err})

			resMsg := err.Error()
			job.ResultMessage = &resMsg
			return tx.SetJobStatus(ctx, job, types.JobStatus.Failed, nil)
		}

		if msg == nil {
			logger.Info("No changes detected for domain update, skipping message sending")
			resMsg := "No changes detected for domain update"
			job.ResultMessage = &resMsg
			return tx.SetJobStatus(ctx, job, types.JobStatus.Completed, nil)
		}
		queue := types.GetTransformQueue(data.Accreditation.AccreditationName)
		headers := map[string]any{
			"reply_to":       "WorkerJobDomainProvisionUpdate",
			"correlation_id": jobId,
		}

		err = server.MessageBus().Send(ctx, queue, msg, headers)
		if err != nil {
			logger.Error(types.LogMessages.MessageSendingToBusFailed, log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return
		}

		logger.Info(types.LogMessages.MessageSendingToBusSuccess, log.Fields{
			types.LogFieldKeys.Domain:               data.Name,
			types.LogFieldKeys.MessageCorrelationID: jobId,
		})

		err = tx.SetJobStatus(ctx, job, types.JobStatus.Processing, nil)
		if err != nil {
			logger.Error(types.LogMessages.UpdateStatusInDBFailed, log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return
		}

		logger.Info(types.LogMessages.UpdateStatusInDBSuccess)

		return
	})
}

// findHandleInDomainInfo finds the handle in the domain info response
func findHandleInDomainInfo(domainInfo *rymessages.DomainInfoResponse, contactType string) string {
	if domainInfo == nil {
		return ""
	}

	for _, c := range domainInfo.GetContacts() {
		if c.GetType() == RYContactTypeMap[contactType] {
			return c.GetId()
		}
	}

	return ""
}

// getDomainInfoIfNeeded retrieves domain info if not already available
func getDomainInfoIfNeeded(ctx context.Context, service *WorkerService, domainInfo **rymessages.DomainInfoResponse, domainName, accreditationName string) error {
	if *domainInfo == nil {
		var err error
		*domainInfo, err = service.getDomainInfo(ctx, domainName, accreditationName)
		return err
	}
	return nil
}

// toDomainUpdateRequest converts DomainUpdateData to ryinterface's DomainUpdateRequest
func toDomainUpdateRequest(ctx context.Context, service *WorkerService, db database.Database, data types.DomainUpdateData, hostObjectSupported bool) (domainUpdateRequest *ryinterface.DomainUpdateRequest, err error) {
	var registrant *string
	domainUpdateRequest = &ryinterface.DomainUpdateRequest{}
	domainUpdateRequest.Name = data.Name

	domain, err := db.GetDomain(ctx, &model.Domain{Name: data.Name})
	if err != nil {
		return
	}

	var domainInfo *rymessages.DomainInfoResponse

	if data.Contacts != nil {
		if len(data.Contacts.All) > 0 {
			// store contacts in a set for faster lookup
			contactSet := make(map[string]string, len(data.Contacts.All))
			for _, c := range data.Contacts.All {
				contactSet[c.Type] = c.Handle
			}

			// new contacts to add
			registrant = processContacts(contactSet, &domainUpdateRequest.Add)

			// old contacts to remove
			removedContacts := make(map[string]string)
			for _, c := range domain.DomainContacts {
				contactType := db.GetDomainContactTypeName(c.DomainContactTypeID)

				// if contact type is staged to be added existing
				// contact for same type must be removed
				if _, ok := contactSet[contactType]; ok {
					handle := c.Handle
					if handle == "" {
						// if handle is empty, we need to get the domain info
						err = getDomainInfoIfNeeded(ctx, service, &domainInfo, data.Name, data.Accreditation.AccreditationName)
						if err != nil {
							return nil, err
						}

						// find handle in domain info if empty in database
						handle = findHandleInDomainInfo(domainInfo, contactType)
					}

					if handle != "" {
						removedContacts[contactType] = handle
					}
				}
			}
			processContacts(removedContacts, &domainUpdateRequest.Rem)
		} else {

			for _, c := range data.Contacts.Add {
				if domainUpdateRequest.Add == nil {
					domainUpdateRequest.Add = &ryinterface.DomainAddRemBlock{}
				}

				if c.Type == "registrant" {
					// registrant can only be changed
					registrantValue := c.Handle
					registrant = &registrantValue
					continue
				}

				contactType := commonmessages.DomainContact_DOMAIN_CONTACT_TYPE_UNSPECIFIED
				if t, ok := RYContactTypeMap[c.Type]; ok {
					contactType = t
				}

				domainUpdateRequest.Add.Contacts = append(domainUpdateRequest.Add.Contacts,
					&commonmessages.DomainContact{
						Type: contactType,
						Id:   c.Handle,
					},
				)
			}

			for _, c := range data.Contacts.Rem {
				if domainUpdateRequest.Rem == nil {
					domainUpdateRequest.Rem = &ryinterface.DomainAddRemBlock{}
				}

				if c.Type == "registrant" {
					// registrant can only be changed
					continue
				}

				handle := c.Handle
				if handle == "" {
					// if handle is empty, need to get the domain info
					err = getDomainInfoIfNeeded(ctx, service, &domainInfo, data.Name, data.Accreditation.AccreditationName)
					if err != nil {
						return nil, err
					}

					// find handle in domain info if empty in database
					handle = findHandleInDomainInfo(domainInfo, c.Type)
				}

				if handle != "" {
					contactType := commonmessages.DomainContact_DOMAIN_CONTACT_TYPE_UNSPECIFIED
					if t, ok := RYContactTypeMap[c.Type]; ok {
						contactType = t
					}

					domainUpdateRequest.Rem.Contacts = append(domainUpdateRequest.Rem.Contacts,
						&commonmessages.DomainContact{
							Type: contactType,
							Id:   handle,
						},
					)
				}
			}

		}
	}

	if data.Pw != nil {
		if domainUpdateRequest.Chg == nil {
			domainUpdateRequest.Chg = &ryinterface.DomainChgBlock{}
		}
		domainUpdateRequest.Chg.Pw = data.Pw
	}

	if registrant != nil {
		if domainUpdateRequest.Chg == nil {
			domainUpdateRequest.Chg = &ryinterface.DomainChgBlock{}
		}
		domainUpdateRequest.Chg.Registrant = registrant
	}

	populateNSAddRemBlock := func(nameservers []*types.Nameserver, b **ryinterface.DomainAddRemBlock) {
		if *b == nil {
			*b = &ryinterface.DomainAddRemBlock{}
		}

		for _, ns := range nameservers {
			if ns == nil {
				continue
			}

			if hostObjectSupported {
				(*b).Nameservers = append((*b).Nameservers, ns.Name)
			} else {
				hostAttribute := &commonmessages.DomainHostAttribute{
					Name:      ns.Name,
					Addresses: ns.IpAddresses,
				}

				(*b).Nsattributes = append((*b).Nsattributes, hostAttribute)
			}
		}
	}

	if len(data.Nameservers.Add) > 0 {
		err = getDomainInfoIfNeeded(ctx, service, &domainInfo, data.Name, data.Accreditation.AccreditationName)
		if err != nil {
			return nil, err
		}

		// Filter out nameservers from data.Nameservers.Add that already exist in domainInfo.Nameservers
		existingNameservers := make(map[string]struct{}, len(domainInfo.GetNameservers()))
		for _, ns := range domainInfo.GetNameservers() {
			existingNameservers[ns] = struct{}{}
		}

		addNameservers := make([]*types.Nameserver, 0, len(data.Nameservers.Add))
		for _, ns := range data.Nameservers.Add {
			if _, exists := existingNameservers[ns.Name]; !exists {
				addNameservers = append(addNameservers, ns)
			}
		}

		populateNSAddRemBlock(addNameservers, &domainUpdateRequest.Add)
	}

	if len(data.Nameservers.Rem) > 0 {
		err = getDomainInfoIfNeeded(ctx, service, &domainInfo, data.Name, data.Accreditation.AccreditationName)
		if err != nil {
			return nil, err
		}

		// Filter out nameservers from data.Nameservers.Rem that do not exist in domainInfo.Nameservers
		existingNameservers := make(map[string]struct{}, len(domainInfo.GetNameservers()))
		for _, ns := range domainInfo.GetNameservers() {
			existingNameservers[ns] = struct{}{}
		}

		remNameservers := make([]*types.Nameserver, 0, len(data.Nameservers.Rem))
		for _, ns := range data.Nameservers.Rem {
			if _, exists := existingNameservers[ns.Name]; exists {
				remNameservers = append(remNameservers, ns)
			}
		}

		populateNSAddRemBlock(remNameservers, &domainUpdateRequest.Rem)
	}

	if data.Locks != nil {
		err = getDomainInfoIfNeeded(ctx, service, &domainInfo, data.Name, data.Accreditation.AccreditationName)
		if err != nil {
			return nil, err
		}
		err = processLocks(data, domainInfo, domainUpdateRequest)
		if err != nil {
			return nil, err
		}
	}

	err = processExtensions(data, domainUpdateRequest)
	if err != nil {
		return nil, err
	}

	// Return nil if the domain update request has no actual changes
	if domainUpdateRequest.Add == nil &&
		domainUpdateRequest.Rem == nil &&
		domainUpdateRequest.Chg == nil &&
		len(domainUpdateRequest.Extensions) == 0 {
		return nil, nil
	}

	return
}

// processContacts takes map of contact handles:types to converts them to ryinterface.DomainAddRemBlock,
// returns registrant handle if exists
func processContacts(contacts map[string]string, domainAddRemBlock **ryinterface.DomainAddRemBlock) *string {
	if *domainAddRemBlock == nil {
		*domainAddRemBlock = &ryinterface.DomainAddRemBlock{}
	}

	var registrant *string

	for t, h := range contacts {
		var contactType commonmessages.DomainContact_DomainContactType

		switch t {
		case "admin":
			contactType = commonmessages.DomainContact_ADMIN
		case "billing":
			contactType = commonmessages.DomainContact_BILLING
		case "tech":
			contactType = commonmessages.DomainContact_TECH
		case "registrant":
			registrantValue := h
			registrant = &registrantValue
			continue
		default:
			contactType = commonmessages.DomainContact_DOMAIN_CONTACT_TYPE_UNSPECIFIED
		}

		c := &commonmessages.DomainContact{
			Type: contactType,
			Id:   h,
		}

		(*domainAddRemBlock).Contacts = append((*domainAddRemBlock).Contacts, c)
	}
	return registrant
}

// process extensions
func processExtensions(data types.DomainUpdateData, domainUpdateRequest *ryinterface.DomainUpdateRequest) (err error) {

	// process secdns extension
	if data.SecDNSData != nil {
		var anySecDNS *anypb.Any
		secdns := &extension.SecdnsUpdateRequest{}

		// process secdns data
		var addData *extension.SecdnsUpdateRequest_Add
		if data.SecDNSData.AddData != nil {
			addData = &extension.SecdnsUpdateRequest_Add{}
			// like provision domain, we don't support a child key data in the ds_data message
			if data.SecDNSData.AddData.DSData != nil {
				dsSet := &extension.DsDataSet{DsData: make([]*extension.DsData, 0, len(*data.SecDNSData.AddData.DSData))}
				for _, ds := range *data.SecDNSData.AddData.DSData {
					dsData := &extension.DsData{
						KeyTag:     uint32(ds.KeyTag),
						Alg:        uint32(ds.Algorithm),
						DigestType: uint32(ds.DigestType),
						Digest:     ds.Digest,
					}
					dsSet.DsData = append(dsSet.DsData, dsData)
				}

				addData = &extension.SecdnsUpdateRequest_Add{
					Data: &extension.SecdnsUpdateRequest_Add_DsSet{
						DsSet: dsSet,
					},
				}

			}

			if data.SecDNSData.AddData.KeyData != nil {
				keySet := &extension.KeyDataSet{KeyData: make([]*extension.KeyData, 0, len(*data.SecDNSData.AddData.KeyData))}

				for _, key := range *data.SecDNSData.AddData.KeyData {
					keyData := &extension.KeyData{
						Flags:    uint32(key.Flags),
						Protocol: uint32(key.Protocol),
						Alg:      uint32(key.Algorithm),
						PubKey:   key.PublicKey,
					}

					keySet.KeyData = append(keySet.KeyData, keyData)
				}

				addData = &extension.SecdnsUpdateRequest_Add{
					Data: &extension.SecdnsUpdateRequest_Add_KeySet{
						KeySet: keySet,
					},
				}
			}
		}
		secdns.Add = addData

		var remData *extension.SecdnsUpdateRequest_Rem
		if data.SecDNSData.RemData != nil {
			if data.SecDNSData.RemData.DSData != nil {
				dsSet := &extension.DsDataSet{DsData: make([]*extension.DsData, 0, len(*data.SecDNSData.RemData.DSData))}
				for _, ds := range *data.SecDNSData.RemData.DSData {
					dsData := &extension.DsData{
						KeyTag:     uint32(ds.KeyTag),
						Alg:        uint32(ds.Algorithm),
						DigestType: uint32(ds.DigestType),
						Digest:     ds.Digest,
					}

					dsSet.DsData = append(dsSet.DsData, dsData)
				}

				remData = &extension.SecdnsUpdateRequest_Rem{
					Data: &extension.SecdnsUpdateRequest_Rem_DsSet{
						DsSet: dsSet,
					},
				}
			}

			if data.SecDNSData.RemData.KeyData != nil {
				keySet := &extension.KeyDataSet{KeyData: make([]*extension.KeyData, 0, len(*data.SecDNSData.RemData.KeyData))}
				for _, key := range *data.SecDNSData.RemData.KeyData {
					keyData := &extension.KeyData{
						Flags:    uint32(key.Flags),
						Protocol: uint32(key.Protocol),
						Alg:      uint32(key.Algorithm),
						PubKey:   key.PublicKey,
					}

					keySet.KeyData = append(keySet.KeyData, keyData)
				}

				remData = &extension.SecdnsUpdateRequest_Rem{
					Data: &extension.SecdnsUpdateRequest_Rem_KeySet{
						KeySet: keySet,
					},
				}
			}
		}
		secdns.Rem = remData

		if data.SecDNSData.MaxSigLife != nil {
			msl := uint32(*data.SecDNSData.MaxSigLife)
			secdns.Chg = &extension.SecdnsUpdateRequest_Chg{
				MaxSigLife: &msl,
			}
		}

		// Only add the SecDNS extension if there's actual data to process
		if secdns.Add != nil || secdns.Rem != nil || secdns.Chg != nil {
			anySecDNS, err = anypb.New(secdns)
			if err != nil {
				return
			}

			if domainUpdateRequest.Extensions == nil {
				domainUpdateRequest.Extensions = map[string]*anypb.Any{"secdns": anySecDNS}
			} else {
				domainUpdateRequest.Extensions["secdns"] = anySecDNS
			}
		}
	}

	return
}

func processLocks(data types.DomainUpdateData, domainInfo *rymessages.DomainInfoResponse, domainUpdateRequest *ryinterface.DomainUpdateRequest) error {
	if data.Locks == nil {
		return nil
	}

	statuses := domainInfo.GetStatuses()
	currentStatusSet := make(map[string]struct{}, len(statuses))
	for _, status := range statuses {
		currentStatusSet[status] = struct{}{}
	}

	for lockName, lockValue := range data.Locks {
		eppStatus, valid := LocksToEppStatus[lockName]
		if !valid {
			continue
		}

		_, statusPresent := currentStatusSet[eppStatus]
		if lockValue {
			if !statusPresent {
				if domainUpdateRequest.Add == nil {
					domainUpdateRequest.Add = &ryinterface.DomainAddRemBlock{}
				}
				domainUpdateRequest.Add.Status = append(domainUpdateRequest.Add.Status, eppStatus)
			}
		} else {
			if statusPresent {
				if domainUpdateRequest.Rem == nil {
					domainUpdateRequest.Rem = &ryinterface.DomainAddRemBlock{}
				}
				domainUpdateRequest.Rem.Status = append(domainUpdateRequest.Rem.Status, eppStatus)
			}
		}
	}

	return nil
}
