package prompt

// OptionsFunc func type used to provide a way to pass optional parameters
type OptionsFunc func(*options)

// options optional prompt parameters
type options struct {
	HideEntered bool
}

func HideEntered() OptionsFunc {
	return func(o *options) {
		o.HideEntered = true
	}
}

func apply(optFns ...OptionsFunc) *options {
	opts := &options{}

	for _, optFn := range optFns {
		optFn(opts)
	}

	return opts
}
