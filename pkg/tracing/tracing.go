package tracing

import (
	"context"

	"github.com/tucowsinc/tdp-shared-go/tracing/oteltrace"
	config "github.com/tucowsinc/tdp-workers-go/pkg/config"
	log "github.com/tucowsinc/tdp-workers-go/pkg/logging"
	"github.com/tucowsinc/tdp-workers-go/pkg/types"
	"go.opentelemetry.io/otel/trace"
)

// Setup initializes the logger with the provided configuration
func Setup(ctx context.Context, config config.Config) (*oteltrace.Tracer, func(context.Context) error, error) {

	tracerConfig := oteltrace.TracerConfig{
		ServiceName:    config.ServiceName,
		EndPoint:       config.TracingEndPoint,
		Sampler:        oteltrace.SamplerParentBased,
		CustomSampler:  nil,
		Enabled:        config.TracingEnabled,
		SpanExporter:   oteltrace.ExporterHTTP,
		CustomExporter: nil,
		Insecure:       config.TracingInsecure,
		TLSConfig:      nil,
		TLSCredentials: nil,
	}

	var otelShutdown func(context.Context) error
	var err error
	var tracer *oteltrace.Tracer
	tracer, otelShutdown, err = oteltrace.SetupOTelSDK(ctx, tracerConfig)
	log.Info("Starting tracer...")
	if err != nil {
		log.Error("error is: ", log.Fields{"error": err})
		return nil, nil, err
	}
	return tracer, otelShutdown, nil
}

func CreateSpanFromMetaData(event *types.JobEvent, tracer *oteltrace.Tracer, name string) (trace.Span, map[string]any) {
	headers := make(map[string]any)
	metaDataHeaders := map[string]any{
		"traceparent": event.Metadata.TraceParent,
		"tracestate":  event.Metadata.TraceState,
	}
	traceHeaders := oteltrace.GetTracerHeader(metaDataHeaders)
	extractedTraceContext := oteltrace.ExtractTraceContext(context.Background(), traceHeaders)
	childSpan, ctx := tracer.CreateSpanFromContext(extractedTraceContext, name)
	tracehead := oteltrace.CustomHeaders{}
	oteltrace.InjectTraceContext(ctx, tracehead)

	for key, value := range tracehead {
		headers[key] = value
	}
	return childSpan, headers

}
