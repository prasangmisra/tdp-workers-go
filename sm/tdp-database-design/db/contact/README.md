- [Contact Module](#contact-module)
  - [Supported Functions](#supported-functions)
    - [Get Contact by ID](#get-contact-by-id)

# Contact Module

## Supported Functions

The contact module supports the following functions

- jsonb_get_contact_by_id

### Get Contact by ID

To query a contact call `jsonb_get_contact_by_id()`. The single argument is the id of the contact. The function returns a JSONB representing the contact.

Example:

```sql
SELECT jsonb_pretty(
    jsonb_get_contact_by_id('7d9a1f49-fb08-43f4-b06b-b5a19b3395c2')
);
```

returns

```json
{
     "id": "7d9a1f49-fb08-43f4-b06b-b5a19b3395c2",
     "fax": "",
     "tags": [
         "tag-one",
         "tag-two",
         "tag-three"
     ],
     "email": "roger.rabbit@hole.org",
     "phone": "+45.987654321",
     "title": "CFO",
     "country": "DK",
     "org_reg": null,
     "org_vat": "XY1234567",
     "language": "en",
     "org_duns": null,
     "birth_date": "1965-03-08",
     "contact_postals": [
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
     "tenant_customer_id": "c1a2b4c3-7986-44f4-8d58-fc3ba337fd54",
     "identity_card_number": "IDC123123123"
 }
```

