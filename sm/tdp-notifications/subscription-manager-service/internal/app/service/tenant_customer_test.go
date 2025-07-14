//go:build integration

package service

import (
	"context"
	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
	"testing"
)

const (
	opensrsTenantCustomerID = "d50ff47e-2a80-4528-b455-6dc5d200ecbe"
	opensrsTenantID         = "26ac88c7-b774-4f56-938b-9f7378cb3eca"

	enomTenantID         = "dc9cb205-e858-4421-bf2c-6e5ebe90991e"
	enomTenantCustomerID = "9fb3982f-1e77-427b-b5ed-e76f676edbd4"
)

func (suite *TestSuite) TestGetTenantID() {
	suite.T().Parallel()
	tests := []struct {
		name         string
		req          string
		expectedResp string
		expectedErrF require.ErrorAssertionFunc
	}{
		{
			name:         "success - providing existing id",
			req:          opensrsTenantCustomerID,
			expectedResp: opensrsTenantID,
			expectedErrF: require.NoError,
		},
		{
			name:         "failure - not found",
			req:          uuid.New().String(),
			expectedResp: "",
			expectedErrF: require.Error,
		},
	}
	for _, tc := range tests {
		suite.T().Run(tc.name, func(t *testing.T) {
			t.Parallel()
			resp, err := suite.srvc.GetTenantID(context.Background(), tc.req)
			tc.expectedErrF(t, err)
			require.Equal(t, tc.expectedResp, resp)
		})
	}
}
