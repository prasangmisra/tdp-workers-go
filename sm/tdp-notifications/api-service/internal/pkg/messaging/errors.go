package messaging

import (
	tcwire "github.com/tucowsinc/tdp-messages-go/message"
)

type BusErr struct {
	*tcwire.ErrorResponse
}

func (b *BusErr) Error() string {
	return b.Message
}
