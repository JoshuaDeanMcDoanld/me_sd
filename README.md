# MESD gem

## Summary

Introduces "MESD" class that works with ManageEngine ServiceDesk Plus without API access. Currently works with SD v8 and only allows to read data.

## Installing

Add this to your Gemfile

`gem "me_sd"`

or run

`gem install me_sd`

## Usage

```
irb(main):001:0> require "me_sd"
=> true
irb(main):002:0> sd = MESD.new({ host: "192.168.0.2", port: "8080", username: "username", password: "password" })
=> #<MESD:0x0000000275b988 @session={:host=>"192.168.0.2", :port=>"8080", :cookie=>"JSESSIONID=2246F4D5A9CE738441FF626B0FA21A56; Path=/"}>
irb(main):003:0> requests = sd.get_all_requests
Getting total 29 requests:
3%..100%
=> [#<Request:0x000000026af390...]
irb(main):004:0> request = Request.new({ session: sd.session, id: 29 })
=> #<Request:0x00000000c4dce0 @id=29, @session={:host=>"192.168.0.150", :port=>"8080", :cookie=>"JSESSIONID=245DFD8E6D6952500DB0138012FEBEFA; Path=/"}>
irb(main):005:0> request.data(:name, :resolution)
=> <... @resolution="resolution", @name="name">
irb(main):006:0> request.name
=> "name"
```

Available properties are `name, author_name, status, priority, create_date, description, resolution`. For each property there are getter like `request.get_property` which loads property "online", while `request.property` shows it's current value.

```
irb(main):007:0> request.status
=> nil
irb(main):008:0> request.get_status
=> :open
```

## TODO

* implement actions like saving resolutions and changing requests' data
* support more properties

## License

MESD is distributed under the MIT-LICENSE.
