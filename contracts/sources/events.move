module suiplace::events;

use std::string::String;
use sui::event;

public struct WheelCratedEvent has copy, drop {
    wheel_id: ID,
    creator: address,
}

public struct CanvasAddedEvent has copy, drop {
    canvas_id: ID,
    index: u64,
}

public struct PixelsPaintedEvent has copy, drop {
    pixels_x: vector<u64>,
    pixels_y: vector<u64>,
    color: vector<String>,
}

public(package) fun emit_wheel_created_event(wheel_id: ID, creator: address) {
    event::emit(WheelCratedEvent {
        wheel_id,
        creator,
    });
}

public(package) fun emit_canvas_added_event(canvas_id: ID, index: u64) {
    event::emit(CanvasAddedEvent {
        canvas_id,
        index,
    });
}

public(package) fun emit_pixels_painted_event(
    pixels_x: vector<u64>,
    pixels_y: vector<u64>,
    color: vector<String>,
) {
    event::emit(PixelsPaintedEvent {
        pixels_x,
        pixels_y,
        color,
    });
}
