package pgevents

type notificationData struct {
	receivedParts int
	totalParts    int
	fullPayload   string
}

type Notification struct {
	ID      string `json:"id"`
	Type    string `json:"type"`
	Payload string `json:"payload"`
}

func (nd *notificationData) reset() {
	nd.receivedParts = 0
	nd.totalParts = 0
	nd.fullPayload = ""
}

type Handler interface {
	HandleNotification(notification *Notification) error
}

type HandlerFunc func(notification *Notification) error

func (f HandlerFunc) HandleNotification(notification *Notification) error {
	return f(notification)
}
