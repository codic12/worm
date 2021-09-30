extern crate x11rb;
use protocol::xproto;
use x11rb::*;
use xproto::ConnectionExt;

#[derive(Clone, Debug)]
struct Geometry {
    pub x: i16,
    pub y: i16,
    pub width: u16,
    pub height: u16,
}

#[derive(Clone, Debug)]
struct MouseMoveStart {
    pub root_x: i16,
    pub root_y: i16,
    pub child: xproto::Window,
    pub detail: u8,
}

type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;

pub struct WindowManager<'a, C: connection::Connection> {
    conn: &'a C,
    scrno: usize,
    root: xproto::Window,
    button_press_geometry: Option<Geometry>,
    mouse_move_start: Option<MouseMoveStart>,
}

impl<'a, C: connection::Connection> WindowManager<'a, C> {
    pub fn new(conn: &'a C, scrno: usize) -> Result<Self> {
        let screen = &conn.setup().roots[scrno];
        for button in &[xproto::ButtonIndex::M1, xproto::ButtonIndex::M3] {
            conn.grab_button(
                false,
                screen.root,
                u32::from(
                    xproto::EventMask::BUTTON_PRESS
                        | xproto::EventMask::BUTTON_RELEASE
                        | xproto::EventMask::POINTER_MOTION,
                ) as u16,
                xproto::GrabMode::ASYNC,
                xproto::GrabMode::ASYNC,
                screen.root,
                x11rb::NONE,
                *button,
                xproto::KeyButMask::MOD4,
            )?
            .check()?;
        }
        conn.change_window_attributes(
            screen.root,
            &xproto::ChangeWindowAttributesAux::new().event_mask(
                xproto::EventMask::SUBSTRUCTURE_REDIRECT | xproto::EventMask::SUBSTRUCTURE_NOTIFY,
            ),
        )?
        .check()?;
        Ok(Self {
            conn,
            scrno,
            root: screen.root,
            button_press_geometry: None,
            mouse_move_start: None,
        })
    }

    pub fn event_loop(&mut self) {
        loop {
            match self.conn.flush() {
                Ok(()) => {}
                Err(_) => continue,
            }
            let ev = match self.conn.wait_for_event() {
                Ok(ev) => ev,
                Err(_) => continue,
            };
            let _ = self.dispatch_event(&ev); // we don't care if it fails, and we don't need to even explicitly continue. just move on! in the future I want to log something here
        }
    }

    fn dispatch_event(&mut self, ev: &protocol::Event) -> Result<()> {
        match ev {
            protocol::Event::MapRequest(ev) => self.handle_map_request(ev)?,
            protocol::Event::ButtonPress(ev) => self.handle_button_press(ev)?,
            protocol::Event::MotionNotify(ev) => self.handle_motion_notify(ev)?,
            _ => {}
        }
        Ok(())
    }

    fn handle_map_request(&self, ev: &xproto::MapRequestEvent) -> Result<()> {
        self.conn.map_window(ev.window)?.check()?;
        Ok(())
    }

    fn handle_button_press(&mut self, ev: &xproto::ButtonPressEvent) -> Result<()> {
        if let Ok(geom) = self.conn.get_geometry(ev.child)?.reply() {
            self.button_press_geometry = Some(Geometry {
                x: geom.x,
                y: geom.y,
                width: geom.width,
                height: geom.height,
            });
            self.mouse_move_start = Some(MouseMoveStart {
                root_x: ev.root_x,
                root_y: ev.root_y,
                child: ev.child,
                detail: ev.detail,
            });
        }
        Ok(())
    }

    fn handle_motion_notify(&mut self, ev: &xproto::MotionNotifyEvent) -> Result<()> {
        let mouse_move_start = self
            .mouse_move_start
            .as_ref()
            .ok_or("motion_notify handler: failed to get value of mouse_move_start, ignoring")?;
        let button_press_geometry = self
            .button_press_geometry
            .as_ref()
            .ok_or("motion_notify handler: failed to get value of button_press_geometry, ignoring")?;
        let (xdiff, ydiff) = (
            ev.root_x - mouse_move_start.root_x,
            ev.root_y - mouse_move_start.root_y,
        );
        let x = button_press_geometry.x as i32
            + if mouse_move_start.detail == 1 {
                xdiff
            } else {
                0
            } as i32;
        let y = (button_press_geometry.y as i16
            + if mouse_move_start.detail == 1 {
                ydiff
            } else {
                0
            }) as i32;
        let width = 1.max(
            button_press_geometry.width as i16
                + if mouse_move_start.detail == 3 {
                    xdiff
                } else {
                    0
                },
        ) as u32;
        let height = 1.max(
            button_press_geometry.height as i16
                + if mouse_move_start.detail == 3 {
                    ydiff
                } else {
                    0
                },
        ) as u32;
        self.conn.configure_window(
            mouse_move_start.child,
            &xproto::ConfigureWindowAux::new()
                .x(x)
                .y(y)
                .width(width)
                .height(height),
        )?;
        Ok(())
    }
}
