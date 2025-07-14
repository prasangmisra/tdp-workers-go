# Template DB Module

This module defines the database structure for managing templates and their related entities. It consists of the following tables:

## Tables

### 1. `language`

- Stores information about supported languages.

### 2. `template_engine`

- Defines the engines used for rendering templates.

### 3. `template_type`

- Categorizes templates into different types.

### 4. `template_status`

- Tracks the status of templates (e.g. draft, published).

### 5. `template`

- Represents the main template entity.

### 6. `section_type`

- Defines types of sections that can be part of a template (e.g. header, body, footer).
- Every type has sequence associated which defines the order of section types in final template

### 7. `section`

- Stores individual sections that can be used in templates.

### 8. `template_section`

- Maps templates to their respective sections.
- Every section mapped with a specific position to properly order sections of same type in final template

### 9. `notification_template_type`

- Maps notification types to corespondent template types.

### 10. `variable_type`

- Defines the types of variables that can be used in templates or sections (e.g. string, integer, date).
- **FOR FUTURE USE**

### 11. `template_variable`

- Stores variables specific to templates.
- Each variable is associated with a `variable_type`.
- **FOR FUTURE USE**

### 12. `section_variable`

- Stores variables specific to sections.
- Each variable is associated with a `variable_type` and linked to a specific section.
- **FOR FUTURE USE**

## Views

### 1. `v_template_section`

- Provides a consolidated view of templates and their associated sections.
- Includes details such as section type, section order for easier querying and rendering.

### 2. `v_template`

- Offers a high-level view of currently valid and ready for usage templates with combined content from all associated sections
- Simplifies access to branded templates for tenant and tenant customers

### 3. `v_notification_template`

- Maps notification types to their corresponding templates.
- Facilitates quick retrieval of templates based on notification requirements.

## Usage

This module is designed to provide a flexible and scalable structure for managing templates and their components. Each table serves a specific purpose, ensuring modularity and ease of maintenance.

Templates are associated with a specific template type. At any given time v_template view will only return ONE template per template type and given tenant_id/tenant_customer_id combination. Templates are selected based on

    - status (only 'published' templates can be used)
    - validity
    - recency

Template can be added in

    - 'draft' status while it is being finalized
    - for future validity to be used from specific point in time

Sections can be reused by associating with multiple templates. Sections are combined into template in following order

    1. Header sections ordered by position set in template_section record
    2. Template body (template record content if provided)
    3. Body sections ordered by position set in template_section record
    4. Footer sections ordered by position set in template_section record

## Dependencies

- Ensure the database schema is properly initialized before using this module.
- Refer to the Makefile scripts for setting up the tables.

## Contributing

Contributions are welcome! Please follow the guidelines in the repository for submitting changes.
