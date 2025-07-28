const std = @import("std");
const Interface = @import("zinterface").Interface;

pub const Shape = struct {
    ptr: *const anyopaque,
    vtable: struct {
        area: *const fn (self: *const anyopaque) f64,
        perimeter: *const fn (self: *const anyopaque) f64,
    },

    /// Computes the area of the shape
    pub fn area(self: *const Shape) f64 {
        return self.vtable.area(self.ptr);
    }

    /// Computes the perimeter of the shape
    pub fn perimeter(self: *const Shape) f64 {
        return self.vtable.perimeter(self.ptr);
    }
};

pub const Circle = struct {
    radius: f64,

    pub fn init(radius: f64) Circle {
        return Circle{
            .radius = radius,
        };
    }

    /// Helper method to wrap the Circle in the Shape interface
    pub fn shape(self: *const Circle) Shape {
        return Interface(Shape, self);
    }

    pub fn area(self: *const Circle) f64 {
        return 3.14159 * self.radius * self.radius;
    }

    pub fn perimeter(self: *const Circle) f64 {
        return 2.0 * 3.14159 * self.radius;
    }
};

pub const Rectangle = struct {
    width: f64,
    height: f64,

    pub fn init(width: f64, height: f64) Rectangle {
        return Rectangle{
            .width = width,
            .height = height,
        };
    }

    /// Helper method to wrap the Rectangle in the Shape interface
    pub fn shape(self: *const Rectangle) Shape {
        return Interface(Shape, self);
    }

    pub fn area(self: *const Rectangle) f64 {
        return self.width * self.height;
    }

    pub fn perimeter(self: *const Rectangle) f64 {
        return 2.0 * (self.width + self.height);
    }
};

pub fn Shapes(allocator: std.mem.Allocator) !void {
    // the interface allows us to treat different shapes uniformly
    var shapes = std.ArrayList(Shape).init(allocator);

    try shapes.append(Circle.init(5.0).shape());
    try shapes.append(Rectangle.init(4.0, 6.0).shape());

    std.debug.print("Shapes:\n", .{});
    for (shapes.items, 0..) |shape, index| {
        std.debug.print("{d}: Area: {d}, Perimeter: {d}\n", .{
            index,
            shape.area(),
            shape.perimeter(),
        });
    }
}
