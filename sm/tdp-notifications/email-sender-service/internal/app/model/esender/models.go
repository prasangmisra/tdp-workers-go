package esender

import (
	"fmt"
	"github.com/samber/lo"
	proto "github.com/tucowsinc/tdp-messages-go/message/common"
	"net/mail"
	"strings"
	"time"
)

const (
	mimeVersion = "1.0"
	contentType = "text/html"
	charset     = "UTF-8"
)

type Message struct {
	Subject string
	Body    string
}

func MessageFromProto(subject, body string) Message {
	return Message{
		Subject: subject,
		Body:    body,
	}
}

type Addresses []mail.Address

func AddressesFromProto(addresses []*proto.Address) Addresses {
	return lo.Map(addresses, func(addr *proto.Address, _ int) mail.Address {
		return AddressFromProto(addr)
	})
}
func AddressFromProto(address *proto.Address) mail.Address {
	return mail.Address{Address: address.GetEmail(), Name: address.GetName()}
}

func (as Addresses) String() string {
	return strings.Join(lo.Map(as, func(a mail.Address, _ int) string {
		return a.String()
	}), ", ")
}

func (as Addresses) ToEmails() []string {
	return lo.Map(as, func(addr mail.Address, _ int) string { return addr.Address })
}

// BuildRFC822
// The msg parameter should be an RFC 822-style email with headers
// first, a blank line, and then the message body. The lines of msg
// should be CRLF terminated. The msg headers should usually include
// fields such as "From", "To", "Subject", and "Cc".  Sending "Bcc"
// messages is accomplished by including an email address in the to
// parameter but not including it in the msg headers.
func (m *Message) BuildRFC822(from, replyTo mail.Address, to, cc, bcc Addresses) []byte {
	msg := strings.Builder{}
	writeOptionalAddr := func(key string, as ...mail.Address) {
		if addrStr := Addresses(as).String(); len(addrStr) > 0 {
			msg.WriteString(key + addrStr + "\r\n")
		}
	}

	msg.WriteString("Date: " + time.Now().UTC().Format(time.RFC822) + "\r\n")
	msg.WriteString("From: " + from.String() + "\r\n")
	msg.WriteString("Subject: " + m.Subject + "\r\n")
	msg.WriteString("MIME-version: " + mimeVersion + ";\r\n")
	msg.WriteString(fmt.Sprintf("Content-Type: %s; charset=%q;\r\n", contentType, charset))

	writeOptionalAddr("Reply-To: ", replyTo)
	writeOptionalAddr("To: ", to...)
	writeOptionalAddr("cc: ", cc...)
	writeOptionalAddr("Bcc: ", bcc...)

	msg.WriteString("\r\n" + m.Body)
	return []byte(msg.String())
}
