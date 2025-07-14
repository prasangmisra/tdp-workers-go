package service

import (
	"testing"

	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/structpb"
)

func anyProtoFromString(t *testing.T, value string) *anypb.Any {
	t.Helper()
	stringValue := structpb.NewStringValue(value)
	protoValue, err := anypb.New(stringValue)
	require.NoError(t, err)
	return protoValue
}
