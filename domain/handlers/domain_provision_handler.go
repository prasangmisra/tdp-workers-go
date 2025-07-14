package handlers

import (
	"encoding/json"
	"fmt"

	"github.com/google/uuid"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	commonmessages "github.com/tucowsinc/tdp-messages-go/message/common"
	"github.com/tucowsinc/tdp-messages-go/message/job"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface"
	"github.com/tucowsinc/tdp-messages-go/message/ryinterface/extension"
	"github.com/tucowsinc/tdp-shared-go/logger"
	"github.com/tucowsinc/tdp-workers-go/pkg/database"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

// DomainProvisionHandler This is a callback handler for the DomainProvision event
// and is in charge of sending the request to the registry interface
func (service *WorkerService) DomainProvisionHandler(server messagebus.Server, message proto.Message) error {
	ctx := server.Context()
	headers := server.Headers()
	span, ctx := service.tracer.CreateSpanFromHeaders(ctx, headers, "DomainProvisionHandler")
	defer service.tracer.FinishSpan(span)

	// we need to type-cast the proto.Message to the wanted type
	request := message.(*job.Notification)
	jobId := request.GetJobId()

	logger := log.CreateChildLogger(log.Fields{
		types.LogFieldKeys.CorrelationID: jobId,
	})

	logger.Info("Starting DomainProvisionHandler for the job")

	data := new(types.DomainData)
	return service.db.WithTransaction(func(tx database.Database) (err error) {
		job, err := tx.GetJobById(ctx, jobId, true)
		if err != nil {
			logger.Error(types.LogMessages.FetchJobByIDFromDBFailed, log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return
		}

		logger = logger.CreateChildLogger(log.Fields{
			types.LogFieldKeys.LogID:   uuid.NewString(),
			types.LogFieldKeys.JobType: *job.Info.JobTypeName,
		})

		logger.Info("Starting domain provision job processing")

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

		// check if the registry supports host objects
		hostObjectSupported, err := getBoolAttribute(tx, ctx, "tld.order.host_object_supported", data.AccreditationTld.AccreditationTldId)
		if err != nil {
			logger.Error("Failed to get host object supported attribute", log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return err
		}

		// create the message to send to the registry interface
		reqBuilder := NewDomainCreateRequestBuilder(data)

		// set the contacts and nameservers
		reqBuilder, err = reqBuilder.
			SetDomainCreateContacts(data.Contacts, logger).
			SetDomainCreateNameservers(data.Nameservers, types.SafeDeref(hostObjectSupported), logger).
			SetDomainCreateExtensions(data, logger)

		if err != nil {
			logger.Error("Failed to set domain create request extensions", log.Fields{
				types.LogFieldKeys.Error: err,
			})
			return err
		}

		// build the message
		msg := reqBuilder.Build()

		// send the message to the registry interface
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

type DomainCreateRequestBuilder struct {
	request *ryinterface.DomainCreateRequest
}

func NewDomainCreateRequestBuilder(data *types.DomainData) *DomainCreateRequestBuilder {
	return &DomainCreateRequestBuilder{
		request: &ryinterface.DomainCreateRequest{
			Name:       data.Name,
			Period:     data.RegistrationPeriod,
			PeriodUnit: types.ToPointer(commonmessages.PeriodUnit_YEAR),
			Pw:         data.Pw,
		},
	}
}

func (b *DomainCreateRequestBuilder) Build() *ryinterface.DomainCreateRequest {
	return b.request
}

func (b *DomainCreateRequestBuilder) SetDomainCreateContacts(domainContacts []types.DomainContact, logger logger.ILogger) *DomainCreateRequestBuilder {
	var registrant string
	var contacts []*commonmessages.DomainContact

	for _, contact := range domainContacts {
		var contactType commonmessages.DomainContact_DomainContactType

		switch contact.Type {
		case "admin":
			contactType = commonmessages.DomainContact_ADMIN
		case "billing":
			contactType = commonmessages.DomainContact_BILLING
		case "tech":
			contactType = commonmessages.DomainContact_TECH
		case "registrant":
			registrant = contact.Handle
			continue
		default:
			logger.Warn("Unknown contact type encountered", log.Fields{
				"type": contact.Type,
				"id":   contact.Handle,
			})
			contactType = commonmessages.DomainContact_DOMAIN_CONTACT_TYPE_UNSPECIFIED
		}

		c := commonmessages.DomainContact{
			Type: contactType,
			Id:   contact.Handle,
		}

		contacts = append(contacts, &c)
	}

	b.request.Registrant = registrant
	b.request.Contacts = contacts

	logger.Info("Domain contacts set successfully", log.Fields{
		"registrant": registrant,
		"contacts":   len(contacts),
	})

	return b
}

func (b *DomainCreateRequestBuilder) SetDomainCreateNameservers(domainNameservers []types.Nameserver, hostObjectSupported bool, logger logger.ILogger) *DomainCreateRequestBuilder {
	// set the nameservers
	if hostObjectSupported {
		for _, nameserver := range domainNameservers {
			b.request.Nameservers = append(b.request.Nameservers, nameserver.Name)
		}
	} else {
		for _, nameserver := range domainNameservers {
			hostAttribute := &commonmessages.DomainHostAttribute{
				Name:      nameserver.Name,
				Addresses: nameserver.IpAddresses,
			}
			b.request.Nsattributes = append(b.request.Nsattributes, hostAttribute)
		}
	}

	logger.Info("Domain nameservers set successfully", log.Fields{
		"hostObjectSupported": hostObjectSupported,
		"nameserversCount":    len(domainNameservers),
	})
	return b
}

func (b *DomainCreateRequestBuilder) SetDomainCreateExtensions(data *types.DomainData, logger logger.ILogger) (*DomainCreateRequestBuilder, error) {
	// initialize the extensions map and error
	var extensions = make(map[string]*anypb.Any)
	var err error

	// iterate through the extensions and set them
	extList := []string{"fee", "launch", "secdns", "idn"}
	for _, ext := range extList {
		switch ext {
		case "fee":
			extensions, err = setFeeExtension(extensions, data.Price, logger)
		case "launch":
			extensions, err = setLaunchExtension(extensions, data.LaunchData, logger)
		case "secdns":
			extensions, err = setSecDNSExtension(extensions, data.SecDNS, logger)
		case "idn":
			extensions, err = setIdnExtension(extensions, data.IdnData, logger)
		default:
			err = fmt.Errorf("unknown extension: %s", ext)
		}
		if err != nil {
			logger.Error("Failed to set domain create extension", log.Fields{
				"extension":              ext,
				types.LogFieldKeys.Error: err,
			})
			return b, err
		}
	}

	// set the extensions
	if len(extensions) > 0 {
		b.request.Extensions = extensions
		logger.Info("Domain extensions set successfully", log.Fields{
			"extensionsCount": len(extensions),
		})
	}

	return b, nil
}

func setFeeExtension(extensions map[string]*anypb.Any, data *types.OrderPrice, logger logger.ILogger) (map[string]*anypb.Any, error) {
	if data == nil {
		return extensions, nil
	}

	feeExtension := &extension.FeeTransformRequest{Fee: []*extension.FeeFee{{Price: types.ToMoneyMsg(data)}}}
	anyFee, err := anypb.New(feeExtension)
	if err != nil {
		logger.Error("Failed to create anypb from fee extension message", log.Fields{types.LogFieldKeys.Message: feeExtension, types.LogFieldKeys.Error: err})
		return extensions, err
	}

	extensions["fee"] = anyFee

	return extensions, nil
}

func setLaunchExtension(extensions map[string]*anypb.Any, data *types.DomainLaunchData, logger logger.ILogger) (map[string]*anypb.Any, error) {
	if data == nil || data.Claims == nil {
		logger.Info("No fee extension data provided; skipping")
		return extensions, nil
	}

	launchExtension := &extension.LaunchCreateRequest{}

	// format launch extension here
	if data.Claims.Type != nil {
		// set the claims type
		switch *data.Claims.Type {
		case "APPLICATION":
			launchExtension.CreateType = extension.LaunchCreateType_LCRT_APPLICATION.Enum()
		case "REGISTRATION":
			launchExtension.CreateType = extension.LaunchCreateType_LCRT_REGISTRATION.Enum()
		default:
			launchExtension.CreateType = extension.LaunchCreateType_LAUNCH_CREATE_TYPE_UNKNOWN.Enum()
		}
	}

	launchExtension.Phase = extension.LaunchPhase_CLAIMS

	// why does the domain claims message have a phase? isn't the phase implied by the message type?
	for _, notice := range data.Claims.Notice {
		launchExtension.Notice = append(launchExtension.Notice, &extension.LaunchNotice{
			NoticeId:     notice.NoticeId,
			ValidatorId:  notice.ValidatorId,
			NotAfter:     timestamppb.New(notice.NotAfter),
			AcceptedDate: timestamppb.New(notice.AcceptedDate),
		})
	}

	anyLaunch, err := anypb.New(launchExtension)
	if err != nil {
		logger.Error("Failed to create anypb from launch extension message", log.Fields{types.LogFieldKeys.Message: launchExtension, types.LogFieldKeys.Error: err})
		return extensions, err
	}

	extensions["launch"] = anyLaunch

	return extensions, nil
}

func setSecDNSExtension(extensions map[string]*anypb.Any, data *types.SecDNSData, logger logger.ILogger) (map[string]*anypb.Any, error) {
	if data == nil {
		return extensions, nil
	}

	secdnsExtension := &extension.SecdnsCreateRequest{}

	if data.DsData != nil {
		dsDataSet := &extension.SecdnsCreateRequest_DsSet{
			DsSet: &extension.DsDataSet{DsData: []*extension.DsData{}},
		}

		// currently the ds_data extension message lacks support for child keydata
		for _, data := range *data.DsData {
			dsRecord := &extension.DsData{
				KeyTag:     uint32(data.KeyTag),
				Alg:        uint32(data.Algorithm),
				DigestType: uint32(data.DigestType),
				Digest:     data.Digest,
			}

			dsDataSet.DsSet.DsData = append(dsDataSet.DsSet.DsData, dsRecord)
		}

		secdnsExtension.Data = dsDataSet
	} else if data.KeyData != nil {
		keyDataSet := &extension.SecdnsCreateRequest_KeySet{
			KeySet: &extension.KeyDataSet{KeyData: []*extension.KeyData{}},
		}

		for _, data := range *data.KeyData {
			keyRecord := &extension.KeyData{
				Flags:    uint32(data.Flags),
				Protocol: uint32(data.Protocol),
				Alg:      uint32(data.Algorithm),
				PubKey:   data.PublicKey,
			}

			keyDataSet.KeySet.KeyData = append(keyDataSet.KeySet.KeyData, keyRecord)
		}

		secdnsExtension.Data = keyDataSet
	}

	if data.MaxSigLife != nil {
		maxSigLife := uint32(*data.MaxSigLife)
		secdnsExtension.MaxSigLife = &maxSigLife
	}

	anySecDNS, err := anypb.New(secdnsExtension)
	if err != nil {
		logger.Error("Failed to create anypb from secdns extension message", log.Fields{types.LogFieldKeys.Message: secdnsExtension, types.LogFieldKeys.Error: err})
		return extensions, err
	}

	extensions["secdns"] = anySecDNS

	return extensions, nil
}

func setIdnExtension(extensions map[string]*anypb.Any, data *types.IdnData, logger logger.ILogger) (map[string]*anypb.Any, error) {
	if data == nil {
		return extensions, nil
	}

	idnExtension := &extension.IdnCreateRequest{Uname: data.IdnUname, Table: data.IdnLang}
	anyIdn, err := anypb.New(idnExtension)
	if err != nil {
		logger.Error("Failed to create anypb from idn extension message", log.Fields{
			types.LogFieldKeys.Message: idnExtension,
			types.LogFieldKeys.Error:   err})
		return extensions, err
	}

	extensions["idn"] = anyIdn

	return extensions, nil
}
