extern crate x11rb;
use crate::{ewmh, ipc};
use protocol::{
    xinerama,
    xproto::{self, ConnectionExt},
};
use x11rb::wrapper::ConnectionExt as OtherConnectionExt;
use x11rb::*;

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

/// A visible, top-level window.
#[derive(Clone, Debug)]
struct Client {
    pub window: xproto::Window,
    pub frame: xproto::Window,
    pub fullscreen: bool,
    pub before_geom: Option<Geometry>,
    pub tags: TagSet,
}

/// Global configuration for the window manager.
#[derive(Clone, Debug)]
struct Config {
    pub border_width: u8,
    pub title_height: u8,
    pub border_pixel: u32,
    pub background_pixel: u32,
}

#[derive(Clone, Debug)]
struct TagSet {
    pub data: [bool; 9],
}

impl Default for TagSet {
    fn default() -> Self {
        Self {
            data: [true, false, false, false, false, false, false, false, false],
        }
    }
}

impl TagSet {
    pub fn view_tag(&mut self, tag: usize) {
        self.data[tag] = true;
    }

    pub fn hide_tag(&mut self, tag: usize) {
        self.data[tag] = false;
    }

    pub fn switch_tag(&mut self, tag: usize) {
        for tag in self.data.iter_mut() {
            *tag = false;
        }
        self.data[tag] = true;
    }
}

type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;

pub struct WindowManager<'a, C>
where
    C: connection::Connection,
{
    conn: &'a C,
    scrno: usize,
    button_press_geometry: Option<Geometry>,
    mouse_move_start: Option<MouseMoveStart>,
    clients: Vec<Client>,
    net_atoms: [xproto::Atom; ewmh::Net::Last as usize],
    ipc_atoms: [xproto::Atom; ipc::IPC::Last as usize],
    config: Config,
    tags: TagSet,
    focused: Option<usize>,
}

impl<'a, C> WindowManager<'a, C>
where
    C: connection::Connection,
{
    pub fn new(conn: &'a C, scrno: usize) -> Result<Self> {
        let screen = &conn.setup().roots[scrno];
        for button in &[xproto::ButtonIndex::M1, xproto::ButtonIndex::M3] {
            match conn
                .grab_button(
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
                    NONE,
                    *button,
                    xproto::KeyButMask::MOD4,
                )?
                .check()
            {
                Ok(()) => {}
                Err(_) => {
                    eprintln!("warn: error grabbing mouse button {:?}. moving/resizing may not function as expected", *button)
                }
            }
        }
        match conn
            .change_window_attributes(
                screen.root,
                &xproto::ChangeWindowAttributesAux::new().event_mask(
                    xproto::EventMask::SUBSTRUCTURE_REDIRECT
                        | xproto::EventMask::SUBSTRUCTURE_NOTIFY,
                ),
            )?
            .check()
        {
            Ok(()) => {}
            Err(_) => {
                return Err(Box::from(
                    "a window manager is already running on this display (failed to capture SubstructureRedirect|SubstructureNotify on root window)",
                ))
            }
        }
        let net_atoms = ewmh::get_ewmh_atoms(conn)?;
        conn.change_property32(
            xproto::PropMode::REPLACE,
            screen.root,
            net_atoms[ewmh::Net::SupportingWMCheck as usize],
            xproto::AtomEnum::WINDOW,
            &[screen.root],
        )?
        .check()?;
        conn.change_property32(
            xproto::PropMode::REPLACE,
            screen.root,
            net_atoms[ewmh::Net::Supported as usize],
            xproto::AtomEnum::ATOM,
            &net_atoms,
        )?
        .check()?;
        Ok(Self {
            conn,
            scrno,
            button_press_geometry: None,
            mouse_move_start: None,
            clients: Vec::new(),
            net_atoms,
            ipc_atoms: ipc::get_ipc_atoms(conn)?,
            config: Config {
                border_width: 3,
                title_height: 15,
                border_pixel: 0x547A97,
                background_pixel: 0x1A1311,
            },
            tags: TagSet::default(),
            focused: None,
        })
    }

    pub fn event_loop(&mut self) {
        loop {
            let _ = self.conn.flush();
            let ev = match self.conn.wait_for_event() {
                Ok(ev) => ev,

                Err(_) => continue,
            };
            let _ = self.dispatch_event(&ev); // we don't care if it fails, and we don't need to even explicitly continue. just move on! in the future I want to log something here, in case of error.
        }
    }

    fn find_client_mut<F>(&mut self, predicate: F) -> Option<(&mut Client, usize)>
    where
        F: Fn(&Client) -> bool,
    {
        for (idx, client) in self.clients.iter_mut().enumerate() {
            if predicate(client) {
                return Some((client, idx));
            }
        }
        None
    }

    fn find_client<F>(&self, predicate: F) -> Option<(&Client, usize)>
    where
        F: Fn(&Client) -> bool,
    {
        for (idx, client) in self.clients.iter().enumerate() {
            if predicate(client) {
                return Some((client, idx));
            }
        }
        None
    }

    fn update_tag_state(&self) -> Result<()> {
        for client in self.clients.iter() {
            'tl: for (j, tag) in client.tags.data.iter().enumerate() {
                if self.tags.data[j] && *tag {
                    self.conn.map_window(client.frame)?.check()?;
                    break 'tl;
                }
                self.conn.unmap_window(client.frame)?.check()?;
            }
        }
        Ok(())
    }

    fn dispatch_event(&mut self, ev: &protocol::Event) -> Result<()> {
        match ev {
            protocol::Event::MapRequest(ev) => self.handle_map_request(ev)?,
            protocol::Event::ButtonPress(ev) => self.handle_button_press(ev)?,
            protocol::Event::MotionNotify(ev) => self.handle_motion_notify(ev)?,
            protocol::Event::ConfigureRequest(ev) => self.handle_configure_request(ev)?,
            protocol::Event::UnmapNotify(ev) => self.handle_unmap_notify(ev)?,
            protocol::Event::DestroyNotify(ev) => self.handle_destroy_notify(ev)?,
            protocol::Event::ClientMessage(ev) => self.handle_client_message(ev)?,
            protocol::Event::ConfigureNotify(ev) => self.handle_configure_notify(ev)?,
            _ => {}
        }
        Ok(())
    }

    fn handle_map_request(&mut self, ev: &xproto::MapRequestEvent) -> Result<()> {
        // we don't want it to already exist if we're gonna reparent it
        let client = self.find_client(|client| client.window == ev.window);
        if client.is_some() {
            self.conn.map_window(ev.window)?.check()?;
            // but it's still a client, so don't change any frame stuff, early return
            return Ok(()); // not really an error
        }
        // check the window type, no dock windows
        let reply = self
            .conn
            .get_property(
                false,
                ev.window,
                self.net_atoms[ewmh::Net::WMWindowType as usize],
                xproto::AtomEnum::ATOM,
                0,
                1024,
            )?
            .reply()?;
        for prop in reply.value {
            if prop == self.net_atoms[ewmh::Net::WMWindowTypeDock as usize] as u8 {
                self.conn.map_window(ev.window)?.check()?;
                return Ok(());
            }
        }
        // Start off by setting _NET_FRAME_EXTENTS
        self.conn
            .change_property32(
                xproto::PropMode::REPLACE,
                ev.window,
                self.net_atoms[ewmh::Net::FrameExtents as usize],
                xproto::AtomEnum::CARDINAL,
                &[
                    self.config.border_width as u32,
                    self.config.border_width as u32,
                    (self.config.border_width + self.config.title_height) as u32,
                    self.config.border_width as u32,
                ],
            )?
            .check()?;
        let screen = &self.conn.setup().roots[self.scrno];
        let geom = self.conn.get_geometry(ev.window)?.reply()?;
        let frame_win = self.conn.generate_id()?;
        let win_aux = xproto::CreateWindowAux::new()
            .event_mask(
                xproto::EventMask::EXPOSURE
                    | xproto::EventMask::SUBSTRUCTURE_REDIRECT
                    | xproto::EventMask::SUBSTRUCTURE_NOTIFY
                    | xproto::EventMask::BUTTON_PRESS
                    | xproto::EventMask::BUTTON_RELEASE
                    | xproto::EventMask::POINTER_MOTION
                    | xproto::EventMask::ENTER_WINDOW,
            )
            .background_pixel(self.config.background_pixel)
            .border_pixel(self.config.border_pixel);
        self.conn.create_window(
            COPY_DEPTH_FROM_PARENT,
            frame_win,
            screen.root,
            geom.x,
            geom.y,
            geom.width,
            geom.height + self.config.title_height as u16,
            3,
            xproto::WindowClass::INPUT_OUTPUT,
            0,
            &win_aux,
        )?;
        self.conn.grab_server()?.check()?;
        self.conn
            .change_save_set(xproto::SetMode::INSERT, ev.window)?
            .check()?;
        self.conn
            .reparent_window(ev.window, frame_win, 0, self.config.title_height as i16)?
            .check()?;
        self.conn.map_window(ev.window)?.check()?;
        self.conn.map_window(frame_win)?.check()?;
        self.conn.ungrab_server()?.check()?;
        self.clients.push(Client {
            window: ev.window,
            frame: frame_win,
            fullscreen: false,
            before_geom: None,
            tags: self.tags.clone(), // this window has whatever tags user is currently on; we want to clone it instead of storing a reference, because the client's tags are independent, this is just a starting point
        });
        self.focused = Some(self.clients.len() - 1);
        self.conn
            .set_input_focus(xproto::InputFocus::PARENT, ev.window, CURRENT_TIME)?
            .check()?;
        self.conn.configure_window(
            frame_win,
            &xproto::ConfigureWindowAux::new().stack_mode(xproto::StackMode::ABOVE),
        )?;
        Ok(())
    }

    fn handle_button_press(&mut self, ev: &xproto::ButtonPressEvent) -> Result<()> {
        let (client, client_idx) = self
            .find_client(|client| client.frame == ev.child)
            .ok_or("button_press: press on non client window, ignoring")?;
        self.conn
            .set_input_focus(xproto::InputFocus::PARENT, client.window, CURRENT_TIME)?
            .check()?;
        self.conn.configure_window(
            client.frame,
            &xproto::ConfigureWindowAux::new().stack_mode(xproto::StackMode::ABOVE),
        )?;
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
        self.focused = Some(client_idx);
        Ok(())
    }

    fn handle_motion_notify(&mut self, ev: &xproto::MotionNotifyEvent) -> Result<()> {
        let (client, _) = self
            .find_client(|client| client.frame == ev.child)
            .ok_or("motion_notify: motion on non client window, ignoring")?;
        if client.fullscreen {
            return Err(Box::from(
                "motion_notify: motion on fullscreen window, ignoring",
            ));
        }
        let mouse_move_start = self
            .mouse_move_start
            .as_ref()
            .ok_or("motion_notify: failed to get value of mouse_move_start, ignoring")?;
        let button_press_geometry = self
            .button_press_geometry
            .as_ref()
            .ok_or("motion_notify: failed to get value of button_press_geometry, ignoring")?;
        // Boring calculate dimensions stuff. Lots of casting. X11 sucks.
        // Max out with 1 on the subtraction operations, because subtraction can
        // yield negative numbers. (So can addition, but we're only dealing with
        // positive operands)
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
        );
        let height = 1.max(
            button_press_geometry.height as i16
                + if mouse_move_start.detail == 3 {
                    ydiff
                } else {
                    0
                }
                - self.config.title_height as i16,
        ); // We subtract -config.title_height here because every time we move the window, +config.title_height gets added for the frame.

        // configure the window, add a +config.title_height for the titlebar
        self.conn.configure_window(
            client.frame,
            &xproto::ConfigureWindowAux::new()
                .x(x)
                .y(y)
                .width(width as u32)
                .height((height + self.config.title_height as i16) as u32),
        )?;
        // and the actual client window inside it, making sure to move it to the appropriate
        // y-offset
        self.conn.configure_window(
            client.window,
            &xproto::ConfigureWindowAux::new()
                .x(0)
                .y(self.config.title_height as i32)
                .width(width as u32)
                .height(height as u32),
        )?;
        // ICCCM § 4.2.3; otherwise, things like firefox menus will be offset when you move but not resize, so we have to send a synthetic ConfigureNotify. a lot of these fields are not specified so I just ignore them with what seems like sensible default values; I doubt the client looks at those anyways.
        self.conn
            .send_event(
                false,
                client.window,
                xproto::EventMask::STRUCTURE_NOTIFY,
                xproto::ConfigureNotifyEvent {
                    above_sibling: NONE,
                    border_width: 0,
                    event: client.window,
                    window: client.window,
                    x: x as i16,
                    y: y as i16,
                    width: width as u16,
                    height: height as u16,
                    override_redirect: false,
                    response_type: xproto::CONFIGURE_NOTIFY_EVENT,
                    sequence: 0,
                },
            )?
            .check()?;
        Ok(())
    }

    fn handle_configure_request(&self, ev: &xproto::ConfigureRequestEvent) -> Result<()> {
        // A window wants us to configure it.
        // Sure, let's configure it.
        self.conn
            .configure_window(
                ev.window,
                &xproto::ConfigureWindowAux::from_configure_request(ev)
                    .sibling(None)
                    .stack_mode(None),
            )?
            .check()?;
        Ok(())
    }

    fn handle_unmap_notify(&mut self, ev: &xproto::UnmapNotifyEvent) -> Result<()> {
        // We get an UnmapNotify when a window unmaps itself from the screen (we can't redirect
        // this to requests, only listen to notify events). In this case, we should also unmap it's
        // parent window, the frame, and remove it from the list of clients.
        let (client, client_idx) = self
            .find_client(|client| client.window == ev.window)
            .ok_or("unmap_notify: unmap on non client window, ignoring")?;
        self.conn.unmap_window(client.frame)?.check()?;
        self.clients.remove(client_idx);
        Ok(())
    }

    fn handle_destroy_notify(&mut self, ev: &xproto::DestroyNotifyEvent) -> Result<()> {
        // The same idea as UnmapNotify; this is generally recieved after UnmapNotify (but not
        // always!), so it won't run. In some cases, though, e.g. when applications are
        // force-killed and the process doesn't have a chance to clean up, we get a DestroyNotify
        // without an UnmapNotify. That's where this comes into play.
        let (client, client_idx) = self
            .find_client(|client| client.window == ev.window)
            .ok_or("destroy_notify: destroy on non client window, ignoring")?;
        self.conn.destroy_window(client.frame)?.check()?;
        self.clients.remove(client_idx);
        Ok(())
    }

    fn handle_client_message(&mut self, ev: &xproto::ClientMessageEvent) -> Result<()> {
        // EWMH § _NET_WM_STATE; sent as a ClientMessage. in this the only thing we handle right
        // now is fullscreen messages.
        if ev.type_ == self.net_atoms[ewmh::Net::WMState as usize] {
            if ev.format != 32 {
                // The spec specifies the format must be 32, this is a buggy and misbehaving
                // application
                return Err(Box::from("client_message: ev.format != 32, ignoring"));
            }
            let (_, client_idx) = self
                .find_client_mut(|client| client.window == ev.window)
                .ok_or("client_message: unmap on non client window, ignoring")?;
            let mut client = &mut self.clients[client_idx]; // we can't use the &mut Client we get & ignore from the find_client_mut method, because then we get errors about multiple mutable borrows... ugh!
            let data = ev.data.as_data32(); // it looks like it's not a simple getter but pulls out the bits and manipulates them, so I don't want to keep fetching it; cache it into an immutable stack local
            if data[1] == self.net_atoms[ewmh::Net::WMStateFullScreen as usize]
                || data[2] == self.net_atoms[ewmh::Net::WMStateFullScreen as usize]
            // EWMH § _NET_WM_STATE § _NET_WM_STATE_FULLSCREEN
            {
                if data[0] == 1 && !client.fullscreen {
                    // we also need to check if the client is not fullscreen just in case it decides to send some random message.
                    client.fullscreen = true;
                    let ss = xinerama::get_screen_size(self.conn, client.window, 0)?.reply()?; // get the screen size
                    let geom = self.conn.get_geometry(client.window)?.reply()?; // the dimensions of the client window; we need this for width and height which we store for un-fullscreening
                    let geom_frame = self.conn.get_geometry(client.frame)?.reply()?; // and the dimensions of it's surrounding frame, we need this for the x and y that we store for un-fullscreening
                    client.before_geom = Some(Geometry {
                        x: geom_frame.x,
                        y: geom_frame.y,
                        width: geom.width,
                        height: geom.height,
                    });
                    // We don't reparent the window out of the frame, because that makes some apps
                    // misbehave. Instead, we resize both to have the coordinates (0, 0) and cover
                    // the whole screen; this seems to sit well with most applications.
                    for win in [client.frame, client.window] {
                        self.conn.configure_window(
                            win,
                            &xproto::ConfigureWindowAux::new()
                                .x(0)
                                .y(0)
                                .width(ss.width)
                                .height(ss.height)
                                .border_width(0),
                        )?;
                    }
                    // And we should change the appropriate property on the window, indicating that
                    // we have successfully recieved and acted on the fullscreen request
                    self.conn
                        .change_property32(
                            xproto::PropMode::REPLACE,
                            client.window,
                            self.net_atoms[ewmh::Net::WMState as usize],
                            xproto::AtomEnum::ATOM,
                            &[self.net_atoms[ewmh::Net::WMStateFullScreen as usize]],
                        )?
                        .check()?;
                } else {
                    client.fullscreen = false;
                    let before_geom = client.before_geom.as_ref().ok_or(
                        "client_message: unfullscreening, but client has no before_geom field (it has not fullscreened before). ignoring.",
                    )?;
                    // Put the frame and window right back where they were
                    self.conn.configure_window(
                        client.frame,
                        &xproto::ConfigureWindowAux::new()
                            .x(before_geom.x as i32)
                            .y(before_geom.y as i32)
                            .width(before_geom.width as u32)
                            .height((before_geom.height + self.config.title_height as u16) as u32)
                            .border_width(self.config.border_width as u32),
                    )?;
                    self.conn.configure_window(
                        client.window,
                        &xproto::ConfigureWindowAux::new()
                            .x(0)
                            .y(self.config.title_height as i32)
                            .width(before_geom.width as u32)
                            .height(before_geom.height as u32)
                            .border_width(0),
                    )?;
                    // Change the property on the window, indicating we've successfully recieved
                    // and gone through with the request to un-fullscreen
                    self.conn
                        .change_property32(
                            xproto::PropMode::REPLACE,
                            client.window,
                            self.net_atoms[ewmh::Net::WMState as usize],
                            xproto::AtomEnum::ATOM,
                            &[],
                        )?
                        .check()?;
                    client.before_geom = None; // so that if somehow this case is hit but before_geom is not set, then the condition at the top returns early with an error
                }
            }
        } else if ev.type_ == self.ipc_atoms[ipc::IPC::ClientMessage as usize] {
            let data = ev.data.as_data32();
            println!("{:?}", data);
            match data {
                data if data[0] == ipc::IPC::KillActiveClient as u32 => {
                    let focused = self
                        .focused
                        .ok_or("client_message: no focused window to kill")?; // todo: get-input_focus
                    self.conn
                        .kill_client(self.clients[focused].window)?
                        .check()?;
                }
                data if data[0] == ipc::IPC::SwitchTag as u32 => {
                    self.tags.switch_tag((data[1] - 1) as usize);
                    self.update_tag_state()?;
                }
                _ => {}
            }
        }
        Ok(())
    }

    fn handle_configure_notify(&self, ev: &xproto::ConfigureNotifyEvent) -> Result<()> {
        let (client, client_idx) = self
            .find_client(|client| client.window == ev.window)
            .ok_or("configure_notify: configure on non client window, ignoring")?;
        self.conn
            .configure_window(
                client.frame,
                &xproto::ConfigureWindowAux::new()
                    .width(ev.width as u32)
                    .height((ev.height + 15) as u32),
            )?
            .check()?;
        Ok(())
    }
}
