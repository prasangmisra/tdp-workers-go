module github.com/tucowsinc/tdp-workers-go

go 1.19

require (
	github.com/alexliesenfeld/health v0.8.0
	github.com/aws/aws-sdk-go-v2 v1.21.0
	github.com/aws/aws-sdk-go-v2/config v1.18.42
	github.com/aws/aws-sdk-go-v2/credentials v1.13.40
	github.com/aws/aws-sdk-go-v2/service/sqs v1.24.5
	github.com/aws/aws-sdk-go-v2/service/sts v1.22.0
	github.com/go-resty/resty/v2 v2.7.0
	github.com/golang/protobuf v1.5.4
	github.com/google/uuid v1.6.0
	github.com/jackc/pgx/v5 v5.5.5
	github.com/jarcoal/httpmock v1.3.1
	github.com/jinzhu/gorm v1.9.16
	github.com/jmoiron/sqlx v1.3.5
	github.com/lib/pq v1.10.7
	github.com/pkg/errors v0.9.1
	github.com/spf13/viper v1.15.0
	github.com/stretchr/testify v1.10.0
	github.com/tucowsinc/tdp-messagebus-go v1.12.3
	github.com/tucowsinc/tdp-messages-go v1.3.83
	github.com/tucowsinc/tdp-shared-go/dns v1.0.10
	github.com/tucowsinc/tdp-shared-go/healthcheck v0.0.2
	github.com/tucowsinc/tdp-shared-go/linq v1.0.0
	github.com/tucowsinc/tdp-shared-go/logger v1.0.18
	github.com/tucowsinc/tdp-shared-go/tracing v1.0.19
	github.com/tucowsinc/tucows-domainshosting-app v1.0.0
	github.com/vishalkuo/bimap v0.0.0-20230512162637-a5362d2f581f
	go.opentelemetry.io/otel/trace v1.17.0
	google.golang.org/protobuf v1.34.2
	gorm.io/driver/postgres v1.5.2
	gorm.io/gorm v1.25.3
)

require (
	github.com/miekg/dns v1.1.61 // indirect
	github.com/tucowsinc/tdp-shared-go/memoizelib v0.1.2
	golang.org/x/mod v0.21.0 // indirect
	golang.org/x/tools v0.26.0 // indirect
)

require (
	github.com/jackc/puddle/v2 v2.2.1 // indirect
	golang.org/x/exp v0.0.0-20240506185415-9bf2ced13842
)

require golang.org/x/sync v0.8.0 // indirect

require (
	github.com/cenkalti/backoff/v4 v4.2.1 // indirect
	github.com/go-logr/logr v1.4.1 // indirect
	github.com/go-logr/stdr v1.2.2 // indirect
	github.com/grpc-ecosystem/grpc-gateway/v2 v2.16.0 // indirect
	github.com/hashicorp/golang-lru/v2 v2.0.7 // indirect
	go.opentelemetry.io/otel v1.17.0 // indirect
	go.opentelemetry.io/otel/exporters/otlp/otlptrace v1.17.0 // indirect
	go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc v1.17.0 // indirect
	go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp v1.17.0 // indirect
	go.opentelemetry.io/otel/exporters/stdout/stdouttrace v1.17.0 // indirect
	go.opentelemetry.io/otel/metric v1.17.0 // indirect
	go.opentelemetry.io/otel/sdk v1.17.0 // indirect
	go.opentelemetry.io/proto/otlp v1.0.0 // indirect
	go.uber.org/multierr v1.11.0 // indirect
	go.uber.org/zap v1.27.0 // indirect
	google.golang.org/genproto/googleapis/api v0.0.0-20230711160842-782d3b101e98 // indirect
	google.golang.org/genproto/googleapis/rpc v0.0.0-20240520151616-dc85e6b867a5 // indirect
	google.golang.org/grpc v1.58.0 // indirect
)

require (
	github.com/aws/aws-sdk-go-v2/feature/ec2/imds v1.13.11 // indirect
	github.com/aws/aws-sdk-go-v2/internal/configsources v1.1.41 // indirect
	github.com/aws/aws-sdk-go-v2/internal/endpoints/v2 v2.4.35 // indirect
	github.com/aws/aws-sdk-go-v2/internal/ini v1.3.43 // indirect
	github.com/aws/aws-sdk-go-v2/service/internal/presigned-url v1.9.35 // indirect
	github.com/aws/aws-sdk-go-v2/service/sso v1.14.1 // indirect
	github.com/aws/aws-sdk-go-v2/service/ssooidc v1.17.1 // indirect
	github.com/aws/smithy-go v1.14.2 // indirect
	github.com/davecgh/go-spew v1.1.2-0.20180830191138-d8f796af33cc // indirect
	github.com/fsnotify/fsnotify v1.6.0 // indirect
	github.com/hashicorp/hcl v1.0.1-vault-5 // indirect
	github.com/jackc/pgerrcode v0.0.0-20220416144525-469b46aa5efa
	github.com/jackc/pgpassfile v1.0.0 // indirect
	github.com/jackc/pgservicefile v0.0.0-20221227161230-091c0ba34f0a // indirect
	github.com/jinzhu/inflection v1.0.0 // indirect
	github.com/jinzhu/now v1.1.5 // indirect
	github.com/jolestar/go-commons-pool/v2 v2.1.2 // indirect
	github.com/magiconair/properties v1.8.7 // indirect
	github.com/mitchellh/mapstructure v1.5.0 // indirect
	github.com/pelletier/go-toml/v2 v2.0.9 // indirect
	github.com/pmezard/go-difflib v1.0.1-0.20181226105442-5d4384ee4fb2 // indirect
	github.com/rabbitmq/amqp091-go v1.10.0 // indirect
	github.com/spf13/afero v1.9.3 // indirect
	github.com/spf13/cast v1.5.0 // indirect
	github.com/spf13/jwalterweatherman v1.1.0 // indirect
	github.com/spf13/pflag v1.0.5 // indirect
	github.com/stretchr/objx v0.5.2 // indirect
	github.com/subosito/gotenv v1.4.2 // indirect
	golang.org/x/crypto v0.28.0 // indirect
	golang.org/x/net v0.30.0 // indirect
	golang.org/x/sys v0.26.0 // indirect
	golang.org/x/text v0.19.0 // indirect
	gopkg.in/ini.v1 v1.67.0 // indirect
	gopkg.in/yaml.v3 v3.0.1 // indirect
)
