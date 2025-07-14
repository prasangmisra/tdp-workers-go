package enqueuer

import (
	"fmt"
	"testing"

	"github.com/tucowsinc/tdp-workers-go/pkg/database/model"
)

func TestDbEnqueuerConfigBuilder_Build(t *testing.T) {
	testCases := []struct {
		name                string
		queryExpression     string
		queryValues         []interface{}
		updateFieldValueMap map[string]interface{}
		queue               string
		batchSize           int
		errorMsg            string
	}{
		{
			name:                "Empty Queue",
			queryExpression:     "SELECT * FROM table",
			queryValues:         []interface{}{1, "example"},
			updateFieldValueMap: map[string]interface{}{"field1": "value1", "field2": 2},
			queue:               "",
			batchSize:           100,
			errorMsg:            "Queue is required",
		},
		{
			name:                "Invalid Batch size",
			queryExpression:     "SELECT * FROM table",
			queryValues:         []interface{}{1, "example"},
			updateFieldValueMap: map[string]interface{}{"field1": "value1", "field2": 2},
			queue:               "example_queue",
			batchSize:           50,
			errorMsg:            fmt.Sprintf("BatchSize must be greater than or equal to %v", DefaultBatchSize),
		},
		{
			name:                "Valid Configuration",
			queryExpression:     "SELECT * FROM table",
			queryValues:         []interface{}{1, "example"},
			updateFieldValueMap: map[string]interface{}{"field1": "value1", "field2": 2},
			queue:               "example_queue",
			batchSize:           100,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			builder := NewDbEnqueuerConfigBuilder[*model.PollMessage]().
				WithQueryExpression(tc.queryExpression).
				WithQueryValues(tc.queryValues).
				WithUpdateFieldValueMap(tc.updateFieldValueMap).
				WithQueue(tc.queue).
				WithBatchSize(tc.batchSize)

			_, err := builder.Build()
			if tc.errorMsg != "" {
				if err == nil {
					t.Error("Expected an error, but got none")
				} else if err.Error() != tc.errorMsg {
					t.Errorf("Expected error message '%s', but got '%s'", tc.errorMsg, err.Error())
				}
			} else {
				if err != nil {
					t.Errorf("Unexpected error: %v", err)
				}
			}
		})
	}
}
