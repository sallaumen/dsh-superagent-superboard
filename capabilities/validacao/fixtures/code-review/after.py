def eligible_suppliers(capabilities, variant_id, destination):
    destination_capabilities = [
        item for item in capabilities if destination in item["destinations"]
    ]
    return [
        item["supplier_id"]
        for item in destination_capabilities
        if item["active"]
    ]
