use xcb;

#[derive(Clone, Debug)]
pub struct Geometry(pub u32, pub u32, pub u32, pub u32);
#[derive(Clone, Debug)]
pub struct MouseMoveStart {
    pub root_x: i16,
    pub root_y: i16,
    pub child: xcb::Window,
    pub detail: u8,
}
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let (conn, _) = xcb::Connection::connect(None)?;
    let screen = conn
        .get_setup()
        .roots()
        .next()
        .ok_or("Failed to get screen")?;
    for button in &[1, 3] {
        xcb::grab_button(
            &conn,
            false,
            screen.root(),
            (xcb::EVENT_MASK_BUTTON_PRESS
                | xcb::EVENT_MASK_BUTTON_RELEASE
                | xcb::EVENT_MASK_POINTER_MOTION) as u16,
            xcb::GRAB_MODE_ASYNC as u8,
            xcb::GRAB_MODE_ASYNC as u8,
            screen.root(),
            xcb::NONE,
            *button,
            xcb::xproto::MOD_MASK_4 as u16,
        );
    }
    conn.flush();
    println!("Button grabbed, starting event loop");
    let mut button_press_geometry: Option<Geometry> = None;
    let mut mouse_move_start: Option<MouseMoveStart> = None;
    loop {
        if let Some(curr_ev) = conn.wait_for_event() {
            println!("Got event: {}", curr_ev.response_type());
            match curr_ev.response_type() {
                xcb::BUTTON_PRESS => {
                    let event: &xcb::ButtonPressEvent = unsafe { xcb::cast_event(&curr_ev) };
                    if let Ok(geometry) = xcb::get_geometry(&conn, event.child()).get_reply() {
                        button_press_geometry = Some(Geometry(
                            geometry.x() as u32,
                            geometry.y() as u32,
                            geometry.width() as u32,
                            geometry.height() as u32,
                        ));
                    }
                    mouse_move_start = Some(MouseMoveStart {
                        root_x: event.root_x(),
                        root_y: event.root_y(),
                        child: event.child(),
                        detail: event.detail(),
                    });
                }
                xcb::BUTTON_RELEASE => {
                    mouse_move_start = None;
                }
                xcb::MOTION_NOTIFY => {
                    let event: &xcb::MotionNotifyEvent = unsafe { xcb::cast_event(&curr_ev) };
                    let mouse_move_start = mouse_move_start.as_ref().unwrap();
                    let attr = button_press_geometry.as_ref().unwrap();
                    let (xdiff, ydiff) = (
                        event.root_x() - mouse_move_start.root_x,
                        event.root_y() - mouse_move_start.root_y,
                    );
                    let x = attr.0 as i32
                        + if mouse_move_start.detail == 1 {
                            xdiff as i32
                        } else {
                            0
                        };
                    let y = attr.1 as i32
                        + if mouse_move_start.detail == 1 {
                            ydiff as i32
                        } else {
                            0
                        };
                    let width = 1.max(
                        attr.2 as i32
                            + if mouse_move_start.detail == 3 {
                                xdiff as i32
                            } else {
                                0
                            },
                    );
                    let height = 1.max(
                        attr.3 as i32
                            + if mouse_move_start.detail == 3 {
                                ydiff as i32
                            } else {
                                0
                            },
                    );
                    xcb::configure_window(
                        &conn,
                        mouse_move_start.child,
                        &[
                            (xcb::CONFIG_WINDOW_X as u16, x as u32),
                            (xcb::CONFIG_WINDOW_Y as u16, y as u32),
                            (xcb::CONFIG_WINDOW_WIDTH as u16, width as u32),
                            (xcb::CONFIG_WINDOW_HEIGHT as u16, height as u32),
                        ],
                    );
                    conn.flush();
                }
                _ => {}
            }
        }
    }
}
