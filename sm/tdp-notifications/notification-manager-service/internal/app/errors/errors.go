package nmerrors

import "errors"

var ErrInvalidNotification = errors.New("could not deserialize notification")
var ErrDatabaseUpdateFailed = errors.New("failed to update notification")
var ErrInvalidFinalStatus = errors.New("invalid final status")
var ErrDBConnection = errors.New("error connecting to DB")
var ErrNotFound = errors.New("not found")
