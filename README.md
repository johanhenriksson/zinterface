# zinterface - typesafe interfaces for zig

The prevalent reasoning in the zig community is that implementing an interface
is "trivial", and that raw dogging your own interfaces with function pointers
is very powerful and just kind of an awesome thing to do. But if you're like me
and you like type safety, there's quite a lot of ground to cover:

- Interface must have a pointer field
- Interface must declare function pointers correctly
- Implementation must implement all methods
- Type check parameters
- Type check return values
- Respect const pointers

and on top of that you might want some utility such as

- Support for optional methods
- Allow users to define custom fields and methods on the interface type
- Allow implementation methods parameters to use specific pointers types in
  place of `*anyopaque` defined in the interface.

Re-implementing this for each interface, or re-generalizing it in each project
quickly becomes a pain. The details are hard to get right, and compile time
checks are difficult to test in zig.

This library attempts to resolve all of these issues by enforcing a pattern and
adding a large number of compile-time checks for interface definitions.

## How to use

The minimum definition of an interface must contain an opaque pointer `ptr`,
and a struct `vtable` containing function pointer definitions. You may add
other fields and methods to your own liking.

```zig
const Adder = struct {
  ptr: *anyopaque,
  vtable: struct {
    add: *const fn(self: *anyopaque, v: i32) i32,
  },
};
```

A minimum implementation simply defines the method with a compatible signature:

```zig
const AddValue = struct {
  value: i32,

  pub fn add(self: *AddValue, v: i32) i32 {
    return v + self.value;
  }
};
```

Then, you can wrap the implementation in an interface using the `Interface()`
function. The `Interface()` call type checks the implementation struct against
the interface definition, and returns an instance of the interface with all
function pointers assigned.

```zig
const Interface = @import("zinterface").Interface;

const adderImpl = AddValue { value: 1 };
const adder = Interface(Adder, adderImpl);

const result = adder.vtable.add(adder.ptr, 1); // result = 2
```

In practice, its customary to to add some helpers to the interface struct for
more ergonomic use:

- A constructor method called `interface`, which avoids imports of
  `Interface` everywhere.
- Dispatch methods that call the vtable methods, passing the self pointer.

```zig
const Adder = struct {
  const Self = @This();

  ptr: *anyopaque,
  vtable: struct {
    add: *const fn(self: *anyopaque, v: i32) i32,
  },

  pub fn interface(ptr: anytype) Self {
      return Interface(Self, ptr);
  }

  pub fn add(self: *Self, v: i32) i32 {
      return self.vtable.add(self.ptr, v);
  }
};
```

Which simplifies the usage significantly:

```zig
const adderImpl = AddValue { value: 1 };
const adder = Adder.interface(adderImpl);

const result = adder.add(1); // result = 2
```

You can also add a method to the implementation struct that converts itself
into the interface type, similar to `.allocator()` in the standard library.

```zig
const AddValue = struct {
  const Self = @This();

  value: i32,

  pub fn add(self: *Self, v: i32) i32 {
    return v + self.value;
  }

  pub fn adder(self: *Self) Adder {
    return Adder.interface(self);
    // .. or ...
    return Interface(Adder, self);
  }
};
```

This trick avoids having to reference the interface type at the call site:

```zig
const adderImpl = AddValue { value: 1 };
const adder = adderImpl.adder();

const result = adder.add(1); // result = 2
```

## Documentation

### Const Interfaces

Interfaces may be declared as constant by adding a `const` modified to the `ptr` field.
This will reject any methods that take a mutable `self` argument.

```zig
const ConstInterface = struct {
  ptr: *const anyopaque,
  vtable: struct {
    read: *const fn(self: *const anyopaque) i32, // ok
    write: *const fn(self: *anyopaque, i32) void, // compile error
  },
};
```

### Optional methods

Interface methods may be declared as optional. In this case, the `Interface()` constructor
won't reject implementations without such a method. Instead, the function pointer will be
set to `null`.

```zig
const OptionalDeinit = struct {
  ptr: *anyopaque,
  vtable: struct {
    method: *const fn(self: *anyopaque) void,
    deinit: ?*const fn(self: *anyopaque) void,
  },
};
```

### Parameter pointer promotion

Implementations may "promote" parameters of type `anyopaque` to more specific types.
This is of course an unsafe operation, which must be used with care. Note that a
const pointer can never be promoted to a mutable pointer.

```zig
const PromotePointer = struct {
  ptr: *anyopaque,
  vtable: struct {
    method: *const fn(self: *anyopaque, userdata: *anyopaque) void,
  },
};

const MyImpl = struct {
  pub fn method(self: *MyImpl, userdata: *KnownType) void {
    // ... use userdata as KnownType ...
  }
};
```

### Custom interface type

Because interfaces are just normal structs, its possible to add any
fields or methods you want on top.

```zig
pub const Deinitializer = struct {
  ptr: *anyopaque,
  vtable: struct {
    deinit: ?*const fn(self: *anyopaque) void,
  },

  // extra fields are okay.
  // be mindful of uninitialized fields!
  destroyed: bool = false,

  pub fn deinit(self: *Deinitializer) void {
    std.debug.assert(!self.destroyed)
    self.destroyed = true;

    if (self.vtable.deinit) |deinitFn| {
      deinitFn();
    }
  }

  // methods unrelated to the interface are also ok:
  pub fn deinitLog(self: *const Deinitalizer) void {
    std.debug.print("Deinitializing!!\n", .{});
    self.deinit();
  }
}
```
