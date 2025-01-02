const std = @import("std");
const gtk = @import("gtk");
const glib = @import("glib");
const gio = @import("gio");
const gobject = @import("gobject");

const ui =
    \\<interface>
    \\  <template class="GtkListItem">
    \\      <property name="child">
    \\          <object class="GtkLabel">
    \\              <binding name="label">
    \\                  <lookup name="string">
    \\                      <lookup name="item">GtkListItem</lookup>
    \\                  </lookup>
    \\              </binding>
    \\          </object>
    \\      </property>
    \\  </template>
    \\</interface>
;

pub fn list(model: *gtk.SelectionModel) *gtk.ListView {
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
    const label = gtk.Label.new("entry");
    item.setChild(label.as(gtk.Widget));
}

fn bind(_: *gtk.SignalListItemFactory, item_: *gobject.Object, _: ?*anyopaque) callconv(.C) void {
    const item: *gtk.ListItem = @ptrCast(item_);
    const label = gtk.ListItem.getChild(item);
    gtk.Label.setText(label, "comida");
}
