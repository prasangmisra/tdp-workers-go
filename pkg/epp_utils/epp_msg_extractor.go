package epp_utils

import (
	"bytes"
	"encoding/xml"
	"strings"

	tcwire "github.com/tucowsinc/tdp-messages-go/message"
	"github.com/tucowsinc/tdp-messages-go/message/common"
	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

// Structs for decoding the relevant part of EPP XML

type EPP struct {
	XMLName  xml.Name `xml:"urn:ietf:params:xml:ns:epp-1.0 epp"`
	Response Response `xml:"response"`
}

type Response struct {
	Result Result `xml:"result"`
}

type Result struct {
	Code   int     `xml:"code,attr"`
	Msg    string  `xml:"msg"`
	Values []Value `xml:"value"`
}

type Value struct {
	Msg string `xml:"msg"`
}

// ExtractMsgsFromXml looks for all <value> elements in the EPP XML and returns their contents
func ExtractMsgsFromXml(xmlBytes []byte) *string {
	decoder := xml.NewDecoder(bytes.NewReader(xmlBytes))

	var epp EPP
	if err := decoder.Decode(&epp); err != nil {
		return nil
	}

	if len(epp.Response.Result.Values) == 0 {
		return nil
	}

	var msgs []string
	for _, value := range epp.Response.Result.Values {
		if value.Msg != "" {
			msgs = append(msgs, value.Msg)
		}
	}

	if len(msgs) == 0 {
		return nil
	}

	result := strings.Join(msgs, ";")
	return &result
}

func GetMessageFromRegistryResponse(registryResponse *common.RegistryResponse) *string {
	if registryResponse == nil {
		return nil
	}

	resMsg := registryResponse.GetEppMessage()
	if eppMsg := ExtractMsgsFromXml(registryResponse.GetXml()); eppMsg != nil {
		resMsg += "; " + *eppMsg
	}

	return &resMsg
}

func SetJobErrorFromRegistryResponse(registryResponse *common.RegistryResponse, job *model.Job, jrd *types.JobResultData) {
	resMsg := GetMessageFromRegistryResponse(registryResponse)
	job.ResultMessage = resMsg
	jrd.SetErrorDetails(&registryResponse.EppCode, resMsg)
}

func SetJobErrorFromRegistryErrorResponse(errorResponse *tcwire.ErrorResponse, job *model.Job, jrd *types.JobResultData) {
	resMsg := errorResponse.GetMessage()
	job.ResultMessage = &resMsg
	code := int32(errorResponse.Code)
	jrd.SetErrorDetails(&code, &resMsg)
}
