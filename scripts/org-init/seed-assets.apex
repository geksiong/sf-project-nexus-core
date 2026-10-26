// Seeds installed assets for the Nexus Asset Explorer (Phase 7, full profile). Idempotent.
if (![SELECT Id FROM Asset WHERE SerialNumber = 'NX-GW-0001' LIMIT 1].isEmpty()) {
    System.debug('Asset seed data already present - skipped');
    return;
}
Map<String, Product2> products = new Map<String, Product2>{
    'IoT Gateway' => new Product2(Name = 'IoT Gateway', ProductCode = 'NX-GW', IsActive = true),
    'Sensor Pack' => new Product2(Name = 'Sensor Pack', ProductCode = 'NX-SP', IsActive = true),
    'Field Tablet' => new Product2(Name = 'Field Tablet', ProductCode = 'NX-FT', IsActive = true)
};
insert products.values();
Map<String, Id> accounts = new Map<String, Id>();
for (Account acc : [SELECT Id, Name FROM Account]) {
    accounts.put(acc.Name, acc.Id);
}
List<List<String>> samples = new List<List<String>>{
    // Account, Asset name, Product, Status, Serial, Quantity, Unit price, Installed (days ago)
    new List<String>{
        'Acme Global Manufacturing',
        'Line 3 gateway',
        'IoT Gateway',
        'Installed',
        'NX-GW-0001',
        '1',
        '12000',
        '400'
    },
    new List<String>{
        'Acme Global Manufacturing',
        'Line 3 sensors',
        'Sensor Pack',
        'Installed',
        'NX-SP-0001',
        '40',
        '250',
        '400'
    },
    new List<String>{
        'Acme Global Manufacturing',
        'Line 4 gateway',
        'IoT Gateway',
        'Shipped',
        'NX-GW-0002',
        '1',
        '12000',
        ''
    },
    new List<String>{
        'Globex Retail Group',
        'Store tablets',
        'Field Tablet',
        'Installed',
        'NX-FT-0001',
        '25',
        '900',
        '120'
    },
    new List<String>{
        'Globex Retail Group',
        'Warehouse gateway',
        'IoT Gateway',
        'Registered',
        'NX-GW-0003',
        '1',
        '12000',
        '30'
    },
    new List<String>{
        'Apex Healthcare Solutions',
        'Clinic sensor kit',
        'Sensor Pack',
        'Purchased',
        'NX-SP-0002',
        '10',
        '250',
        ''
    }
};
List<Asset> assets = new List<Asset>();
for (List<String> s : samples) {
    assets.add(
        new Asset(
            AccountId = accounts.get(s[0]),
            Name = s[1],
            Product2Id = products.get(s[2]).Id,
            Status = s[3],
            SerialNumber = s[4],
            Quantity = Decimal.valueOf(s[5]),
            Price = Decimal.valueOf(s[6]),
            InstallDate = String.isBlank(s[7]) ? null : Date.today().addDays(-Integer.valueOf(s[7]))
        )
    );
}
insert assets;
System.debug('Seeded ' + products.size() + ' products and ' + assets.size() + ' assets');
