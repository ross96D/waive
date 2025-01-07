const std = @import("std");
const gtk = @import("gtk");
const gio = @import("gio");
const glib = @import("glib");
const gdk = @import("gdk");
const gobject = @import("gobject");
const pass = @import("passphrase/root.zig");
const storage = @import("database/storage.zig");
const utils = @import("utils.zig");

// test passpharse 123
const NULL = @as(*allowzero void, @ptrFromInt(0));

const css_styles: [*:0]const u8 = @embedFile("styles.css");

const data_example = &[_]?[*:0]const u8{
    "comida",  "sentido", "comida",  "sentido", "comida",  "sentido", "sentido", "sentido",
    "sentido", "sentido", "sentido", "sentido", "sentido", "sentido", "sentido", "sentido",
    "sentido", "sentido", "sentido", "sentido", "sentido", "sentido", "sentido", "sentido",
    "sentido", "sentido", "sentido", "sentido", "sentido", "sentido", "sentido", "sentido",
    "sentido", "sentido", "sentido", "sentido", "sentido", "sentido", "sentido", "sentido",
    null,
};

var application: *gtk.Application = undefined;
var allocator_instance = std.heap.GeneralPurposeAllocator(.{}){};
pub const allocator = allocator_instance.allocator();

fn set_layer(window: *gtk.Window) void {
    const l = @cImport(@cInclude("gtk4-layer-shell.h"));
    // Before the window is first realized, set it up to be a layer surface
    const w: [*c]l.GtkWindow = @ptrCast(window);
    l.gtk_layer_init_for_window(w);

    // Order below normal windows
    l.gtk_layer_set_layer(w, l.GTK_LAYER_SHELL_LAYER_OVERLAY);

    l.gtk_layer_set_keyboard_mode(w, l.GTK_LAYER_SHELL_KEYBOARD_MODE_EXCLUSIVE);
}

fn gtk_quit(_: *gio.SimpleAction, _: ?*glib.Variant, app: *gtk.Application) callconv(.C) void {
    const list = app.getWindows();
    glib.List.foreach(list, &close_window, null);
}

fn close_window(window: ?*anyopaque, _: ?*anyopaque) callconv(.C) void {
    const w: *gtk.Window = @ptrCast(@alignCast(window));
    w.destroy();
}

pub fn init_application(app: *gtk.Application) void {
    application = app;

    utils.init(allocator);

    const action = gio.SimpleAction.new("quit", null);
    defer action.unref();
    _ = gio.SimpleAction.signals.activate.connect(action, *gtk.Application, &gtk_quit, application, .{});
    gio.ActionMap.addAction(application.as(gio.ActionMap), action.as(gio.Action));

    const accel = gdk.keyvalName(gdk.KEY_Escape);
    const accels = [1:0][*c]const u8{accel};
    gtk.Application.setAccelsForAction(application, "app.quit", @ptrCast(&accels));

    const css_provider = gtk.CssProvider.new();
    css_provider.loadFromString(css_styles);
    gtk.StyleContext.addProviderForDisplay(
        gdk.Display.getDefault().?,
        css_provider.as(gtk.StyleProvider),
        gtk.STYLE_PROVIDER_PRIORITY_USER,
    );
}

pub const SearchPassword = struct {
    var search_password_window: ?*gtk.Window = null;
    var list: List = undefined;
    var search_entry: *gtk.Entry = undefined;
    pub fn get() *gtk.Window {
        if (search_password_window) |w| {
            return w;
        }
        const window = gtk.ApplicationWindow.new(application);
        const w = window.as(gtk.Window);
        search_password_window = w;

        w.setDefaultSize(500, 300);

        set_layer(w);

        // ---- CREATE BOX ----
        const main_box = gtk.Box.new(gtk.Orientation.vertical, 5);
        gtk.Widget.setName(main_box.as(gtk.Widget), "outer-box");
        gtk.Box.setSpacing(main_box, 3);
        gtk.Window.setChild(w, main_box.as(gtk.Widget));
        gtk.Widget.setSizeRequest(main_box.as(gtk.Widget), 500, 0);

        { // ---- CREATE ENTRY ----
            const entry = gtk.Entry.new();
            search_entry = entry;
            _ = gtk.Editable.signals.changed.connect(entry, ?*anyopaque, cb_entry_change, null, .{});

            gtk.Entry.setPlaceholderText(entry, "search for link or password");
            _ = gtk.Entry.signals.activate.connect(entry, *gtk.Window, entry_enter, w, .{});
            gtk.Widget.setHexpand(entry.as(gtk.Widget), 1);
            gtk.Box.append(main_box, entry.as(gtk.Widget));

            // ---- CUSTOM FOCUS EVENT ----
            const controller = gtk.EventControllerKey.new();
            _ = gtk.EventControllerKey.signals.key_pressed.connect(controller, *gtk.Entry, global_key_press, entry, .{});
            gtk.Widget.addController(w.as(gtk.Widget), controller.as(gtk.EventController));
        }

        { // ---- CREATE LIST ----
            list = List{ .cb_filter = cb_list_filter };
            const list_widget = list.create_list();

            const scrolled = gtk.ScrolledWindow.new();
            gtk.Widget.setVexpand(scrolled.as(gtk.Widget), 1);
            gtk.ScrolledWindow.setChild(scrolled, list_widget.as(gtk.Widget));

            gtk.Box.append(main_box, scrolled.as(gtk.Widget));
        }

        return search_password_window.?;
    }

    fn cb_entry_change(_: *gtk.Entry, _: ?*anyopaque) callconv(.C) void {
        // TRIGGER FILTER
        const new_filter = gtk.CustomFilter.new(list.cb_filter, null, null);
        list.filter.setFilter(new_filter.as(gtk.Filter));
    }

    fn cb_list_filter(p_item: *gobject.Object, _: ?*anyopaque) callconv(.C) c_int {
        const item: *gtk.StringObject = @ptrCast(p_item);

        const text = getText(search_entry.as(gtk.Editable));
        const text_slc = utils.to_slice(text);

        const item_str = item.getString();
        const item_slc = utils.to_slice(item_str);

        if (text_slc.len == 0) return 1;

        const length = @min(text_slc.len, item_slc.len);

        const score = utils.string_distance_score(
            allocator,
            text_slc[0..length],
            item_slc[0..length],
        ) catch unreachable;

        return if (score > 0.5) 1 else 0;
    }

    fn entry_enter(entry: *gtk.Entry, window: *gtk.Window) callconv(.C) void {
        const buffer = entry.getBuffer();
        const text = buffer.getText();

        const dbus = @import("passphrase/dbus_secret_service.zig");

        if (eql(text, "")) {
            const param = allocator.create(pass.GetPassphraseData) catch unreachable;
            param.* = pass.GetPassphraseData{
                .cb = null,
                .data = null,
                .window = window,
            };
            pass.get_passphrase(param);
        } else if (eql(text, "-1")) {
            std.debug.print("delete_passphras\n", .{});
            dbus.delete_passphrase(on_delete_passphrase, null);
        } else {
            std.debug.print("search password\n", .{});
        }
    }

    fn on_delete_passphrase(_: bool, p_error: ?*glib.Error, _: ?*anyopaque) void {
        std.log.info("on_delete_passphrase", .{});
        if (p_error) |err| {
            std.log.err("on_delete_passphrase {}", .{err});
        }
    }

    fn global_key_press(
        _: *gtk.EventControllerKey,
        keyval: c_uint,
        _: c_uint,
        _: gdk.ModifierType,
        entry: *gtk.Entry,
    ) callconv(.C) c_int {
        const unicode = gdk.keyvalToUnicode(keyval);
        if (unicode == 0) return 0;

        if (unicode > 255) {
            if (gtk.Widget.isFocus(entry.as(gtk.Widget)) == 1) {
                return 0;
            }
            _ = gtk.Widget.grabFocus(entry.as(gtk.Widget));
            return 0;
        }
        if (std.ascii.isPrint(@intCast(unicode))) {
            if (gtk.Widget.isFocus(entry.as(gtk.Widget)) == 1) {
                return 0;
            }

            _ = gtk.Widget.grabFocus(entry.as(gtk.Widget));
            var buffer = entry.getBuffer();
            _ = buffer.insertText(buffer.getLength(), @ptrCast(&[1:0]u8{@intCast(unicode)}), 1);
            gtk.Editable.setPosition(entry.as(gtk.Editable), @intCast(buffer.getLength()));

            return 0;
        }
        return 0;
    }

    const List = struct {
        gtk_list: *gtk.StringList = undefined,
        filter: *gtk.FilterListModel = undefined,

        cb_filter: gtk.CustomFilterFunc,

        /// using global isntance here because the List
        // var gtk_list: *gtk.StringList = undefined;

        fn create_list(self: *List) *gtk.ListView {
            const model_gio = gtk.StringList.new(null);
            self.gtk_list = model_gio;

            const filter = gtk.CustomFilter.new(self.cb_filter, null, null);
            const model_filter = gtk.FilterListModel.new(model_gio.as(gio.ListModel), filter.as(gtk.Filter));
            self.filter = model_filter;

            const model = gtk.SingleSelection.new(model_filter.as(gio.ListModel));

            const param = allocator.create(pass.GetPassphraseData) catch unreachable;
            param.* = pass.GetPassphraseData{
                .cb = cb_fill_list,
                .data = @ptrCast(self),
                .window = search_password_window.?,
            };

            pass.get_passphrase(param);

            return list_view(model.as(gtk.SelectionModel));
        }

        fn cb_fill_list(p_res: ?[*:0]u8, p_error: ?*glib.Error, p_data: ?*anyopaque) void {
            if (p_error) |err| {
                std.log.err("cb_set_password {d} {s}", .{ err.f_code, err.f_message orelse "unknown error" });
                return;
            }
            std.debug.assert(p_res != null);
            const passphrase = p_res.?;
            const store = storage.Storage.init(utils.to_slice(passphrase), allocator) catch unreachable;

            const self: *List = @ptrCast(@alignCast(p_data));

            store.get_all_namespaces(allocator, self.gtk_list) catch unreachable;
        }

        pub fn list_view(model: *gtk.SelectionModel) *gtk.ListView {
            const item_factory = create_factory();
            return gtk.ListView.new(model, item_factory.as(gtk.ListItemFactory));
        }

        fn create_factory() *gtk.ListItemFactory {
            const factory = gtk.SignalListItemFactory.new();
            _ = gtk.SignalListItemFactory.signals.setup.connect(factory, ?*anyopaque, setup, null, .{});
            _ = gtk.SignalListItemFactory.signals.bind.connect(factory, ?*anyopaque, setup, null, .{});
            return factory.as(gtk.ListItemFactory);
        }

        fn setup(_: *gtk.SignalListItemFactory, item_: *gobject.Object, _: ?*anyopaque) callconv(.C) void {
            const item: *gtk.ListItem = @ptrCast(item_);
            const objnull: ?*gtk.StringObject = @ptrCast(item.getItem());
            if (objnull) |obj| {
                const label = gtk.Label.new(obj.getString());
                item.setChild(label.as(gtk.Widget));
            }
        }

        fn bind(_: *gtk.SignalListItemFactory, item_: *gobject.Object, _: ?*anyopaque) callconv(.C) void {
            const item: *gtk.ListItem = @ptrCast(item_);
            const objnull: ?*gtk.StringObject = @ptrCast(item.getItem());
            if (objnull) |obj| {
                const label = gtk.Label.new(obj.getString());
                item.setChild(label.as(gtk.Widget));
            }
        }
    };
};

pub const AddPassword = struct {
    var add_password_window: ?*gtk.Window = null;
    var add_password_widgets: ?Widgets = null;
    const Widgets = extern struct {
        namespace: *gtk.Entry = undefined,
        password: *gtk.PasswordEntry = undefined,
        confirm: *gtk.PasswordEntry = undefined,
    };
    pub fn get() *gtk.Window {
        if (add_password_window) |w| return w;
        add_password_widgets = Widgets{};

        const window = gtk.ApplicationWindow.new(application);
        const w = window.as(gtk.Window);
        add_password_window = w;

        set_layer(w);

        // ---- CREATE BOX ----
        const box = gtk.Box.new(.vertical, 5);

        gtk.Widget.setName(box.as(gtk.Widget), "outer-box");
        gtk.Widget.setMarginBottom(box.as(gtk.Widget), 5);
        gtk.Widget.setMarginStart(box.as(gtk.Widget), 5);
        gtk.Widget.setMarginEnd(box.as(gtk.Widget), 5);
        { // ---- CREATE HEADER
            const frame = gtk.Frame.new(null);
            frame.setLabelAlign(0.5);

            const header_box = gtk.Box.new(.horizontal, 5);
            gtk.Widget.setHalign(header_box.as(gtk.Widget), .center);
            gtk.Widget.setMarginTop(header_box.as(gtk.Widget), 5);
            gtk.Widget.setMarginBottom(header_box.as(gtk.Widget), 5);

            { // Add label with icon
                const main_label = gtk.Label.new("Add password");
                const icon = gtk.Image.newFromIconName("dialog-password");
                header_box.append(icon.as(gtk.Widget));
                header_box.append(main_label.as(gtk.Widget));
            }

            frame.setLabelWidget(header_box.as(gtk.Widget));

            frame.setChild(box.as(gtk.Widget));
            gtk.Window.setChild(w, frame.as(gtk.Widget));
        }

        { // ---- CREATE NAMESPACE PASSWORD ----
            const namespace_box = gtk.CenterBox.new();
            const namespace_label = gtk.Label.new("namespace: ");
            namespace_label.setJustify(.right);
            gtk.Widget.setHexpand(namespace_label.as(gtk.Widget), 1);
            gtk.Widget.setHalign(namespace_label.as(gtk.Widget), .end);

            const namespace_entry = gtk.Entry.new();
            gtk.Widget.setName(namespace_entry.as(gtk.Widget), "namespace");
            add_password_widgets.?.namespace = namespace_entry;
            namespace_box.setStartWidget(namespace_label.as(gtk.Widget));
            namespace_box.setEndWidget(namespace_entry.as(gtk.Widget));

            box.append(namespace_box.as(gtk.Widget));
        }
        { // ---- CREATE INSERT PASSWORD FIELD ----
            const password_box = gtk.CenterBox.new();
            const password_label = gtk.Label.new("password: ");
            password_label.setJustify(.right);
            gtk.Widget.setHexpand(password_label.as(gtk.Widget), 1);
            gtk.Widget.setHalign(password_label.as(gtk.Widget), .end);

            const password_entry = gtk.PasswordEntry.new();
            password_entry.setShowPeekIcon(1);
            gtk.Widget.setName(password_entry.as(gtk.Widget), "password");
            add_password_widgets.?.password = password_entry;
            password_box.setStartWidget(password_label.as(gtk.Widget));
            password_box.setEndWidget(password_entry.as(gtk.Widget));

            box.append(password_box.as(gtk.Widget));
        }
        { // ---- CREATE CONFIRM PASSWORD FIELD ----
            const password_box = gtk.CenterBox.new();
            const password_label = gtk.Label.new("confirm: ");
            password_label.setJustify(.right);
            gtk.Widget.setHexpand(password_label.as(gtk.Widget), 1);
            gtk.Widget.setHalign(password_label.as(gtk.Widget), .end);

            const password_entry = gtk.PasswordEntry.new();
            password_entry.setShowPeekIcon(1);
            gtk.Widget.setName(password_entry.as(gtk.Widget), "confirm_password");
            add_password_widgets.?.confirm = password_entry;
            password_box.setStartWidget(password_label.as(gtk.Widget));
            password_box.setEndWidget(password_entry.as(gtk.Widget));

            box.append(password_box.as(gtk.Widget));
        }
        { // ---- CREATE ACCEPT BUTTON ----
            const button = gtk.Button.new();
            gtk.Widget.setName(button.as(gtk.Widget), "accept_button");
            _ = gtk.Button.signals.clicked.connect(button, *Widgets, cb_accept, &add_password_widgets.?, .{});

            const button_box = gtk.Box.new(.horizontal, 5);
            { // ---- Add label with icon ----
                const icon = gtk.Image.newFromIconName("emblem-ok-symbolic");
                button_box.append(icon.as(gtk.Widget));
                const label = gtk.Label.new("Accept");
                button_box.append(label.as(gtk.Widget));
            }
            gtk.Widget.setHalign(button_box.as(gtk.Widget), .center);
            gtk.Button.setChild(button, button_box.as(gtk.Widget));
            gtk.Button.setCanShrink(button, 1);
            gtk.Widget.setHexpand(button.as(gtk.Widget), 0);

            box.append(button.as(gtk.Widget));
        }
        return add_password_window.?;
    }

    fn cb_accept(_: *gtk.Button, widgets: *Widgets) callconv(.C) void {
        var invalid: bool = false;
        if (check_is_emtpy(widgets.namespace.as(gtk.Editable))) {
            invalid = true;
            addCssClass(widgets.namespace, "invalid");
        }
        if (check_is_emtpy(widgets.password.as(gtk.Editable))) {
            invalid = true;
            addCssClass(widgets.password, "invalid");
        }
        if (check_is_emtpy(widgets.confirm.as(gtk.Editable))) {
            invalid = true;
            addCssClass(widgets.confirm, "invalid");
        }
        const password = widgets.password.as(gtk.Editable);
        const confirm = widgets.confirm.as(gtk.Editable);
        if (!eql(password.getText(), confirm.getText())) {
            invalid = true;
            addCssClass(widgets.confirm, "invalid");
            addCssClass(widgets.password, "invalid");
        }
        if (invalid) {
            _ = glib.timeoutAddOnce(2000, cb_reset_css_classes, widgets);
            return;
        }
        const cb_data = allocator.create(pass.GetPassphraseData) catch unreachable;
        cb_data.* = pass.GetPassphraseData{
            .cb = cb_set_password,
            .data = application,
            .window = add_password_window.?,
        };
        pass.get_passphrase(cb_data);
    }

    fn cb_set_password(p_res: ?[*:0]u8, p_error: ?*glib.Error, p_data: ?*anyopaque) void {
        if (p_error) |err| {
            std.log.err("cb_set_password {d} {s}", .{ err.f_code, err.f_message orelse "unknown error" });
            return;
        }
        const app: *gtk.Application = @ptrCast(@alignCast(p_data));

        std.debug.assert(p_res != null);
        const res = p_res.?;

        const store = storage.Storage.init(utils.to_slice(res), allocator) catch unreachable; // TODO handle gracefully
        store.store(.{
            .namespace = utils.to_slice(getText(add_password_widgets.?.namespace.as(gtk.Editable))),
            .password = utils.to_slice(getText(add_password_widgets.?.password.as(gtk.Editable))),
        }) catch unreachable; // TODO handle gracefully;

        const wlist = app.getWindows();
        glib.List.foreach(wlist, &close_window, null);
    }

    fn cb_reset_css_classes(p_data: ?*anyopaque) callconv(.C) void {
        const widgets: *Widgets = @ptrCast(@alignCast(p_data));
        removeCssClass(widgets.namespace, "invalid");
        removeCssClass(widgets.password, "invalid");
        removeCssClass(widgets.confirm, "invalid");
    }
};

fn addCssClass(widget: anytype, class: [*:0]const u8) void {
    gtk.Widget.addCssClass(widget.as(gtk.Widget), class);
}

fn removeCssClass(widget: anytype, class: [*:0]const u8) void {
    gtk.Widget.removeCssClass(widget.as(gtk.Widget), class);
}

fn check_is_emtpy(editable: *gtk.Editable) bool {
    return eql(editable.getText(), "");
}

fn getText(editable: *gtk.Editable) [*:0]const u8 {
    return editable.getText();
}

fn eql(a: [*:0]const u8, b: [*:0]const u8) bool {
    var i: usize = 0;
    var a_elem: u8 = a[i];
    var b_elem: u8 = b[i];
    while (a_elem != 0 and b_elem != 0) {
        if (a_elem != b_elem) return false;
        i += 1;
        a_elem = a[i];
        b_elem = b[i];
    }
    return a_elem == b_elem;
}
