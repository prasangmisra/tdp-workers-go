# Frequently Asked Questions

## Tucows Domain Platform Database

### Tables

#### Why there is a table `order_contact` instead of `order_item_create_contact`?

Even though we currently only support one order item per order, if we ever have multiple order items per order, they can all refer back to the same contact, avoiding the need to duplicate them. Having them in an `order_contact` table makes them universally accessible by all order items.

#### Why there is no table order_item_create_nameserver?

Currently name servers are part of the metadata that is needed to register a domain name. To have a `order_item_create_nameserver` table it would mean that we would need to have a product named *nameserver* with the appropriate verb (create, renew, etc.) in the `order_type` table.

This information with the corresponding table name is summarized in a view called: `v_order_product_type`, which includes a column `rel_name`.

#### Why there are tables create_domain_contact/create_domain_nameservers instead of create_domain_contact_plan/create_domain_nameserver_plan?

From top to bottom, the `order` table captures the generic information about an order. `order_item` should not be used directly, this is where the `order_item_create_domain` table comes into play, which inherits from `order_item` and contains the *line detail* that is needed to provision a domain name, however some elements cannot be mapped in the same row, due to one-to-many relationships, which is why additional tables are needed to complement the information.

For the use case of a domain creation, this includes:

* `create_domain_contact`: maps the row from the `order_item_create_domain` table with thhe contacts present in the order: `order_contact`.

* `create_domain_nameserver`: is the list of name servers that are to be used for the domain registration.

* `order_host_addr`: contain the ip addresses needed to provision the server.

All of the tables that start with `create_domain*` are simply sub components needed to complement the `order_item_create_domain` rows.

The `create_domain_plan` is part of another component that sets the prioritization in which the elements that conform a domain registration should be processed. This table contains a list of objects to be provisioned; `reference_id` is the id of the row on another table, which will depend on the object type.


#### Which are the tables to store an order?

This will depend on the order type. For a domain registration (order domain create), it will be:

* `order`
* `order_item_create_domain`
* `order_contact`
* 'order_contact_postal'
* `create_domain_contact`
* 'order_host'
* 'order_host_addr'
* `create_domain_nameserver`


In addition to these tables, the system will store information about the execution plan, or order in which the objects will be processed, on the table:

* create_domain_plan

To summarize some of this information there is a view called: `v_order_create_domain` which can be used to query information about this type of orders. Similarly there is a table `v_order_renew_domain`.


Which are the tables to control the order processing?

**create_domain_plan** contains the plan itself.

The configuration on how the items should be processed comes from the **order_item_strategy** table which contains entries for each type of order.

The priority is set with the `provision_order` column.

#### Which are the tables to hold the resulting objects?

The resulting objects, are stored in the following tables:

* **domain**
* **contact**
* **contact_postal**
* **domain_contact**
* **host**
* **host_addr**
* **domain_host**

