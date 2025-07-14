- [Order Module](#order-module)
  - [Supported Products](#supported-products)
  - [Contact Orders](#contact-orders)
    - [Create Contact](#create-contact)

# Order Module

## Supported Products and Order Types

The order module supports the following products and their respective order types:

- contact
  - create
  - update (implementation pending)
  - delete (implementation pending)
- domain (implementation pending)
- host (implementation pending)
- ssl (implementation pending)

## Contribution
### Code distribution
- Stored Procedures (`stored-procedures/`): This directory contains SQL files defining stored procedures used by the order module.
  - `helper/`: Contains any misc functions; no triggers.
  - `validation/`: Contains only triggers.
  - `processing/`: Contains order executing processing plan.

## Contact Orders

### Create Contact

To place a create contact order call `create_contact_order_from_jsonb()`. The single argument is of type JSONB. The function returns the id of the created order, of type UUID.

Example (listing all keys currently recognized from the JSONB):

```sql
SELECT create_contact_order_from_jsonb('
    {
        "tenant_customer_id":   "c1a2b4c3-7986-44f4-8d58-fc3ba337fd54",
        "customer_user_id":     "aa46257d-3b05-4737-b41f-99dd88e3ddaa",
        "contact_type":         "individual",
        "title":                "CFO",
        "org_reg":              null,
        "org_vat":              "XY1234567",
        "org_duns":             null,
        "email":                "roger.rabbit@hole.org",
        "phone":                "+45.987654321",
        "fax":                  "",
        "country":              "DK",
        "language":             "en",       ,
        "tags":                 ["tag-one", "tag-two", "tag-three"],
        "documentation":        ["unknown purpose", "useless doc"],
        "order_contact_postals": [
            {
                "city": "København",
                "state": null,
                "address1": "Rosenvængets Allé 42",
                "address2": null,
                "address3": null,
                "org_name": "Some-Company",
                "last_name": "Østerbro",
                "first_name": "Tómas",
                "postal_code": "1234",
                "is_international": false
            },
            {
                "city": "Copenhagen",
                "state": null,
                "address1": "Rosenvaengets Alley 42",
                "address2": null,
                "address3": null,
                "org_name": "Some-Company",
                "last_name": "Oesterbro",
                "first_name": "Tomas",
                "postal_code": "1234",
                "is_international": true
            }
        ],
        "identity_card_number": "IDC123123123",
        "birth_date":           "1965-03-08",
        "birth_country":        "IS",
        "tld_de_type":          "de_type_1",
        "tld_asia_type":        "ascio_type_2",
        "tld_az_type":          "az_type_3",
        "tld_ca_type":          "ca_type_4",
        "tld_nl_type":          "nl_type_5",
        "tld_uk_type":          "uk_type_6"
    }
'::JSONB);
```

To query a create contact order call `jsonb_get_create_contact_order_by_id()`. The single argument is the id of the order. The function returns a JSONB representing the order.

Example:

```sql
SELECT jsonb_pretty(
    jsonb_get_create_contact_order_by_id('04505cbf-4e9f-4460-9047-8a706002f9dc')
);
```

returns

```json
{
     "id": "04505cbf-4e9f-4460-9047-8a706002f9dc",
     "fax": "",
     "tags": [
         "tag-one",
         "tag-two",
         "tag-three"
     ],
     "type": {
        "name": "create"
     },
     "email": "roger.rabbit@hole.org",
     "phone": "+45.987654321",
     "title": "CFO",
     "status": {
        "name": "successful"
     },
     "country": "DK",
     "org_reg": null,
     "org_vat": "XY1234567",
     "language": "en",
     "org_duns": null,
     "birth_date": "1965-03-08",
     "created_date": "2023-03-21T18:28:39.756726Z",
     "updated_date": "2023-03-21T18:28:39.756726Z",
     "order_contact_postals": [
         {
             "city": "København",
             "state": null,
             "address1": "Rosenvængets Allé 42",
             "address2": null,
             "address3": null,
             "org_name": "Some-Company",
             "last_name": "Østerbro",
             "first_name": "Tómas",
             "postal_code": "1234",
             "is_international": false
         },
         {
             "city": "Copenhagen",
             "state": null,
             "address1": "Rosenvaengets Alley 42",
             "address2": null,
             "address3": null,
             "org_name": "Some-Company",
             "last_name": "Oesterbro",
             "first_name": "Tomas",
             "postal_code": "1234",
             "is_international": true
         }
     ],
     "tld_de_type": ".de-type",
     "contact_type": "individual",
     "birth_country": "IS",
     "documentation": [
         "unknown purpose",
         "useless doc"
     ],
     "customer_user_id": "aa46257d-3b05-4737-b41f-99dd88e3ddaa",
     "tenant_customer_id": "c1a2b4c3-7986-44f4-8d58-fc3ba337fd54",
     "identity_card_number": "IDC123123123"
 }
```

Alternatively order can be retrieved by `jsonb_get_order_by_id()`. The single argument is the id of the order. The function returns product name and a JSONB representing the order.

Example:

```sql
SELECT jsonb_pretty(
    jsonb_get_order_by_id('04505cbf-4e9f-4460-9047-8a706002f9dc')
);
```

returns "contact" text and

```json
{
     "id": "04505cbf-4e9f-4460-9047-8a706002f9dc",
     "fax": "",
     "tags": [
         "tag-one",
         "tag-two",
         "tag-three"
     ],
     "type": {
        "name": "create"
     },
     "email": "roger.rabbit@hole.org",
     "phone": "+45.987654321",
     "title": "CFO",
     "status": {
        "name": "successful"
     },
     "country": "DK",
     "org_reg": null,
     "org_vat": "XY1234567",
     "language": "en",
     "org_duns": null,
     "birth_date": "1965-03-08",
     "created_date": "2023-03-21T18:28:39.756726Z",
     "updated_date": "2023-03-21T18:28:39.756726Z",
     "order_contact_postals": [
         {
             "city": "København",
             "state": null,
             "address1": "Rosenvængets Allé 42",
             "address2": null,
             "address3": null,
             "org_name": "Some-Company",
             "last_name": "Østerbro",
             "first_name": "Tómas",
             "postal_code": "1234",
             "is_international": false
         },
         {
             "city": "Copenhagen",
             "state": null,
             "address1": "Rosenvaengets Alley 42",
             "address2": null,
             "address3": null,
             "org_name": "Some-Company",
             "last_name": "Oesterbro",
             "first_name": "Tomas",
             "postal_code": "1234",
             "is_international": true
         }
     ],
     "tld_de_type": ".de-type",
     "contact_type": "individual",
     "birth_country": "IS",
     "documentation": [
         "unknown purpose",
         "useless doc"
     ],
     "customer_user_id": "aa46257d-3b05-4737-b41f-99dd88e3ddaa",
     "tenant_customer_id": "c1a2b4c3-7986-44f4-8d58-fc3ba337fd54",
     "identity_card_number": "IDC123123123"
 }
```



To query a created contact call `jsonb_get_contact_by_id()`. See the [Contact README](../contact#get-contact-by-id) for details.

### Update Contact

TBD

### DELETE Contact

TBD

## Domain Orders

TBD

## Host Orders

TBD

## SSL Orders

TBD
