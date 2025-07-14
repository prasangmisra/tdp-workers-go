package epp_utils

import (
	"testing"

	"github.com/stretchr/testify/assert"

	"github.com/tucowsinc/tdp-messages-go/message/common"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
)

func TestExtractMsgFromXml(t *testing.T) {
	tests := []struct {
		name     string
		xmlInput []byte
		want     *string
	}{
		{
			name: "Valid XML with value and msg",
			xmlInput: []byte(`
				<epp xmlns="urn:ietf:params:xml:ns:epp-1.0">
					<response>
						<result code="2001">
							<msg>Command completed successfully; action pending</msg>
							<value>
								<msg>Domain is pending verification</msg>
							</value>
						</result>
					</response>
				</epp>
			`),
			want: types.ToPointer("Domain is pending verification"),
		},
		{
			name: "Valid XML without value",
			xmlInput: []byte(`
				<epp xmlns="urn:ietf:params:xml:ns:epp-1.0">
					<response>
						<result code="1000">
							<msg>Command completed successfully</msg>
						</result>
					</response>
				</epp>
			`),
			want: nil,
		},
		{
			name: "Valid XML with empty value msg",
			xmlInput: []byte(`
				<epp xmlns="urn:ietf:params:xml:ns:epp-1.0">
					<response>
						<result code="2001">
							<msg>Command completed successfully; action pending</msg>
							<value>
								<msg></msg>
							</value>
						</result>
					</response>
				</epp>
			`),
			want: nil,
		},
		{
			name:     "Invalid XML",
			xmlInput: []byte(`This is not valid XML`),
			want:     nil,
		},
		{
			name:     "Empty XML",
			xmlInput: []byte(``),
			want:     nil,
		},
		{
			name: "Valid XML with multiple values",
			xmlInput: []byte(`
				<epp xmlns="urn:ietf:params:xml:ns:epp-1.0">
					<response>
						<result code="2001">
							<msg>Command completed successfully; action pending</msg>
							<value>
								<msg>First error message</msg>
							</value>
							<value>
								<msg>Second error message</msg>
							</value>
							<value>
								<msg>Third error message</msg>
							</value>
						</result>
					</response>
				</epp>
			`),
			want: types.ToPointer("First error message;Second error message;Third error message"),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := ExtractMsgsFromXml(tt.xmlInput)
			if tt.want == nil {
				assert.Nil(t, got)
			} else {
				assert.NotNil(t, got)
				assert.Equal(t, *tt.want, *got)
			}
		})
	}
}

func TestGetMessageFromRegistryResponse(t *testing.T) {
	tests := []struct {
		name             string
		registryResponse *common.RegistryResponse
		expected         *string
	}{
		{
			name: "Response with both EPP message and XML value message",
			registryResponse: &common.RegistryResponse{
				Xml: []byte(`<?xml version="1.0" encoding="UTF-8"?>
					<epp xmlns="urn:ietf:params:xml:ns:epp-1.0">
						<response>
							<result code="2308">
								<msg>Data management policy violation</msg>
								<value>
									<msg>The domain is blocked by Registry policy</msg>
								</value>
							</result>
						</response>
					</epp>`),
				EppMessage: "Command failed",
			},
			expected: types.ToPointer("Command failed; The domain is blocked by Registry policy"),
		},
		{
			name: "Response with EPP message but no XML value message",
			registryResponse: &common.RegistryResponse{
				Xml: []byte(`<?xml version="1.0" encoding="UTF-8"?>
					<epp xmlns="urn:ietf:params:xml:ns:epp-1.0">
						<response>
							<result code="2308">
								<msg>Data management policy violation</msg>
							</result>
						</response>
					</epp>`),
				EppMessage: "Command failed",
			},
			expected: types.ToPointer("Command failed"),
		},
		{
			name: "Response with invalid XML but valid EPP message",
			registryResponse: &common.RegistryResponse{
				Xml:        []byte(`This is not valid XML`),
				EppMessage: "Command failed",
			},
			expected: types.ToPointer("Command failed"),
		},
		{
			name: "Response with empty XML and EPP message",
			registryResponse: &common.RegistryResponse{
				Xml:        []byte(``),
				EppMessage: "Command failed",
			},
			expected: types.ToPointer("Command failed"),
		},
		{
			name: "Response with empty EPP message but valid XML message",
			registryResponse: &common.RegistryResponse{
				Xml: []byte(`<?xml version="1.0" encoding="UTF-8"?>
					<epp xmlns="urn:ietf:params:xml:ns:epp-1.0">
						<response>
							<result code="2308">
								<msg>Data management policy violation</msg>
								<value>
									<msg>The domain is blocked by Registry policy</msg>
								</value>
							</result>
						</response>
					</epp>`),
				EppMessage: "",
			},
			expected: types.ToPointer("; The domain is blocked by Registry policy"),
		},
		{
			name:             "Nil registry response",
			registryResponse: nil,
			expected:         nil,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := GetMessageFromRegistryResponse(tt.registryResponse)

			if tt.expected == nil {
				assert.Nil(t, result)
			} else {
				assert.NotNil(t, result)
				assert.Equal(t, *tt.expected, *result)
			}
		})
	}
}
