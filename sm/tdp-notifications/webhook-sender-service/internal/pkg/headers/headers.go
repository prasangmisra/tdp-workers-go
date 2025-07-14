package headers

import (
	"reflect"
	"strconv"

	"github.com/tucowsinc/tdp-messagebus-go/pkg/messagebus"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

const (
	EXPIRES_IN_MS = "expires_in_ms"
	X_RETRY       = "x_retry"
)

type Headers struct {
	XRetry int `header:"x_retry"`
}

func extractRetryCount(anyValue *anypb.Any) (int, error) {
	var stringVal wrapperspb.StringValue
	if err := anyValue.UnmarshalTo(&stringVal); err != nil {
		return 0, err
	}
	intValue, err := strconv.Atoi(stringVal.Value)
	if err != nil {
		return 0, err
	}
	return intValue, nil
}

func ParseHeaders(s messagebus.Server) (Headers, error) {
	headers := s.Envelope().Headers
	parsed := Headers{}
	structType := reflect.TypeOf(parsed)
	structValue := reflect.ValueOf(&parsed).Elem()

	for _, field := range reflect.VisibleFields(structType) {
		tag := field.Tag.Get("header")

		if tag != "" {

			if anyValue, ok := headers[tag]; ok {
				switch tag {
				case "x_retry":
					retryCount, err := extractRetryCount(anyValue)
					if err != nil {
						return Headers{}, err
					}
					structValue.FieldByIndex(field.Index).SetInt(int64(retryCount))
				default:
				}
			}
		}
	}

	return parsed, nil
}
