package validators

import (
	"testing"

	"github.com/go-playground/validator/v10"
	"github.com/stretchr/testify/assert"
)

func TestPassword(t *testing.T) {
	type testItem struct {
		Password string `validate:"strong_password"`
	}

	validate := validator.New()
	err := validate.RegisterValidation("strong_password", validatePassword)
	assert.NoError(t, err)

	testCases := []struct {
		test  testItem
		valid bool
	}{
		{testItem{"1"}, false},
		{testItem{"1234567890123"}, false},
		{testItem{"t2345678"}, false},
		{testItem{"tG345"}, false},
		{testItem{"3tG3=5abHnD$@c"}, true},
		{testItem{"3tG3l5abHnD$P"}, false},  // less then 14
		{testItem{"3tG3f5abHnDxOc"}, false}, // only letters and numbers no Special Chars
		{testItem{"3tG3f5%bhndxoc"}, true},  // only 1 uppercase still works
		{testItem{"3tGcfq@bhndxoc"}, true},  // only 1 digit still works
		{testItem{"hjSbPx+t?7NNhKx_XRyTF1jWAxtaA2.8$XzAh}e%*ywz?X-tFBAG0E]Le$5H.8U!DhNLX&2d$P" +
			"LHuvAM4Jhh-2]aX*?c,x0&uw..ukPD@bupGNbAc9xV9pC@1vMLh_LZf8"}, false}, // longer than max size
	}
	for _, tc := range testCases {
		err := validate.Struct(tc.test)

		if tc.valid == true {
			assert.NoError(t, err, tc)
		} else {
			assert.Error(t, err, tc)
		}

	}
}
