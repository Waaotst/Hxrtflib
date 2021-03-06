// The first insert into the text editor must happen at the beggining index
// The default tag will not get applied if this doesn't happen

// The tag is an id which represents a style

// override_style is state used to determine if the next char
// being inserted should take the last chars style (default)
// or use some other style.

// Note:
// A word with 3 letters has 4 cursor positions. We consider
// cursor positions and pass them around the program.
// Word "abc" can be detcted when the cursor is at 1.0 and 1.4,
// but to read the tags or chars you need to use 1.0 to 1.3
// So we use _index, to refer to the "cursor" and _T_index to automaticlaly handle this conversion for us

// TODO stylid and tag is used ambiguosly..
// TODO on_char_insert might be simplifiable
// TODO use interfaces and export the tester
// TODO remove default_tag always being insert
// TODO what happens on backspace? and del?

package hxrtflib;

import hxrtflib.Editor;
import hxrtflib.Util;
import hxrtflib.Assert;

@:expose
class Hxrtflib {
  static var consumers = new Array();
  public var ed:EditorInterface;

  public function new(editor) {
    ed = editor;
    ed.styles = new Map();
    var map = new Style();
    ed.styles.set(Globals.DEFAULT_TAG, map);
  }

  // if a text editor has 5 chars -> 12345
  // There are 6 possiblle cursor locations
  // The last position has no tag, so we read
  // from the previous one..
  function _hx_tag_at_index(row, col) {
    var tag = ed._hx_tag_at_index(row, col);
    if (tag == Globals.NOTHING) {
      // TODO read from previous row
      if (col != Globals.START_COL) {
        tag = ed._hx_tag_at_index(row, col -1);
      }
    }
    return tag;
  }

  function tag_at_T_index(row, col) {
    var tag;
    if (col != Globals.START_COL) {
      tag = ed._hx_tag_at_index(row, col-1);
    }
    else {
      tag = ed._hx_tag_at_index(row, col);
    }
    return tag;
  }

  // Adds a tag on insert, (the libraray must do the insert)
  public function on_char_insert(event, row, col) {
    if (ed._hx_move_key(event)) {
      consumer_run(row, col);
    }
    // event, will be passed to ignored_key, use this
    // to decide if a char needs to be inserted
    if (ed._hx_ignore_key(event)) {
      return;
    }
    var override_style = override_style_get();
    if (override_style != Globals.NOTHING) {
      tag_set_override(override_style, row, col);
      override_style_reset();
      return;
    }
    else if (col == Globals.START_COL) {
      insert_when_cursor_at_start(row);
    }
    else if (ed._hx_is_selected(row, col)) {
      insert_when_selected(row, col);
    }
    else {
      var tag = tag_at_T_index(row, col);
      // FIXME THIS STATE HSOULD NEVER BE REACHED.. - should be sset in  inset when cursor at start
      if (tag == Globals.NOTHING) {
        insert_when_no_tag(row, col);
      }
      else {
        tag_set(tag, row, col);
      }
    }
  }


  // NOTE, row and col must be of the final position, care of event loop
  public function on_mouse_click(row, col) {
    override_style_reset();
    consumer_run(row, col);
  }


  public function insert_when_cursor_at_start(row) {
    var col = Globals.START_COL;
    var char_at_cur = ed._hx_char_at_index(row, col);
    var tag = ed._hx_tag_at_index(row, col);

    if (char_at_cur == "\n"
        || char_at_cur == Globals.EOF) {
        if (row == Globals.START_ROW) {
          // First insert into empty editor
          if (tag == Globals.NOTHING) {
            insert_when_no_tag(row, col);
            return;
          }
          // Existing tag at 1.0
          tag_set(tag, row, Globals.START_COL);
        }
        // Get tag from the previous line
        else {
          tag = ed._hx_tag_at_index(row - 1, ed._hx_last_col(row - 1));
          tag_set(tag, row, Globals.START_COL);
        }
      }
  }


  // TODO look at how tags get read.. seems funky

  // Allows us to insert charachters to arbitrary positions
  // And the tags will be applied properly
  function insert_when_no_tag(row, col) {
    var tag = Globals.DEFAULT_TAG;
    // Apply default tag to the inserted char
    tag_set(tag, row, col);
    // Apply default tag to the NEXT char
    // This is important as amount of position a cursor can have
    // is charachters + 1;
    // tag_set(tag, row, col+1);
  }


  public function insert_when_selected(row:Int, col:Int) {
    var sel_pos:Pos = ed._hx_first_selected_index(row, col);
    var tag = ed._hx_tag_at_index(sel_pos.row, sel_pos.col);
    tag_set(tag, sel_pos.row, sel_pos.col);
  }


  // set the tag, taking the override into account
  function tag_set_override(tag:Int, row, col) {
    if (override_style_get() == Globals.NOTHING) {
      ed._hx_tag_add(tag, row, col);
    }
    // Use the override tag
    else {
      ed._hx_tag_add(override_style_get(), row, col);
      override_style_reset();
    }
  }

  // set the tag
  function tag_set(tag:Int, row, col) {
    Assert.assert(override_style_get() == Globals.NOTHING);
    ed._hx_tag_add(tag, row, col);
  }


  function override_style_reset() {
    ed.override_style = Globals.NOTHING;
  }


  function override_style_set(style) {
    ed.override_style = style;
  }


  public function override_style_get() {
    return ed.override_style;
  }


  // Apply a Style change to the current curosor position
  public dynamic function style_change(change_key, change_value) {
    var cursor:Pos = ed._hx_insert_cursor_get();
    // Style some selection
    if (ed._hx_is_selected(cursor.row, cursor.col)) {
      Assert.assert(override_style_get() == Globals.NOTHING);
      style_with_selection(change_key, change_value, cursor);
    }
    // Either apply style or set the override style
    else {
      style_no_selection(change_key, change_value, cursor);
    }
    // NOTE requires to be run in ev because new tag isn't applied
    consumer_run(cursor.row, cursor.col);
  }

  function style_no_selection(change_key, change_value, cursor) {
    var style_id;
    // Style when cursor at extremity
    if (is_word_extremity(cursor.row, cursor.col)) {
      style_id = style_from_change(change_key, change_value, cursor.row, cursor.col);

      // Set The override_style
      if (override_style_get() == Globals.NOTHING) {
        override_style_set(style_id);
      }
      // Reset the override_style
      else {
        override_style_reset();
      }

    }
    // Style when cursor in middle of a word
    else {
      // TODO delete this.. Any cursor move should invalidate the override_style - /rename override_style to extrimty_override
      override_style_reset();

      var left = word_start_get(cursor.row, cursor.col);
      var right = word_end_get(cursor.row, cursor.col);
      // FIXME this isn't true..
      var start:Pos = {row: cursor.row, col: left};
      // FIXME this isn't true
      var end:Pos = {row: cursor.row, col: right};
      style_word_range(change_key, change_value, start, end);
    }

  }

  // Style a word when it is selected
  function style_with_selection(change_key, change_value, cursor) {
    var sel = ed._hx_sel_index_get(cursor.row, cursor.col);
    style_word_range_sel(change_key, change_value, sel.start, sel.end);
  }


  function style_word_range(change_key, change_value, start, end) : StyleId {
    // apply style to every char based on the style at cursor
    // + 1 because we have to include the end index
    var style_id;
    var cursor:Pos = ed._hx_insert_cursor_get();
    style_id = style_from_change(change_key, change_value,
                                 cursor.row, cursor.col);

    // TODO extract a metod to iterate positions
    var _start_col, _end_col;
    for (r in start.row...end.row+1) {
      // Set the iteration indexes
      if (r == start.row) {
        _start_col = start.col;
      }
      else {
        _start_col = Globals.START_COL;
      }
      if (r == end.row) {
        _end_col = end.col;
      }
      else {
        _end_col = ed._hx_last_col(r);
      }
      for (c in _start_col..._end_col) {
        tag_set(style_id, r,  c);
      }
    }
    return style_id;
  }

  function style_word_range_sel(change_key, change_value, start, end) {
    // apply style to every char based on the style at cursor
    // + 1 because we have to include the end index
    var style_id;

    // TODO extract a metod to iterate positions
    var _start_col, _end_col;
    for (r in start.row...end.row+1) {
      // Set the iteration indexes
      if (r == start.row) {
        _start_col = start.col;
      }
      else {
        _start_col = Globals.START_COL;
      }
      if (r == end.row) {
        _end_col = end.col;
      }
      else {
        _end_col = ed._hx_last_col(r);
      }
      for (c in _start_col..._end_col) {
        style_id = style_from_change(change_key, change_value, r, c);
        tag_set(style_id, r,  c);
      }
    }
  }


  function style_from_change(change_key, change_value, row, col) : StyleId {
    // given a requested change return the new/existing style
    var se:StyleExists = style_exists(change_key, change_value, row, col);
    if (se.exists) {
      return se.style_id;
    }
    else {
      return style_new(se.style);
    }
  }


  function get_tag_of_next_char(row, col) : StyleId {
    var style_id;
    if (override_style_get() != Globals.NOTHING) {
      style_id = override_style_get();
    }
    else {
      style_id = tag_at_T_index(row, col);
      // Pressing arrows in an empty widget etc
      if (style_id == Globals.NOTHING) {
        return Globals.DEFAULT_TAG;
      }
    }
    return style_id;
  }

  public function style_exists(change_key, change_value, row, col) : StyleExists {
    // Detects weather a change will require a new style to be made
    // FIXME implicitly relies on override_style

    // The style we will add or remove our change from
    var base_style_id = get_tag_of_next_char(row, col);
    Assert.assert(ed.styles.exists(base_style_id));
    var base_style:Style = ed.styles.get(base_style_id);
    // remove or add the change to the position?
    var remove:Bool;
    // The map is empty
    if (base_style == null) {
      remove = false;
    }
    else if (change_value == base_style.get(change_key)) {
      remove = true;
    }
    else {
      remove = false;
    }

    var required_style = new Style();
    // Make a copy of the base style
    if (base_style != null) {
      for (key in base_style.keys()) {
        var value = base_style.get(key);
        required_style.set(key, value);
      }
    }

    // Build the required style
    if (remove) {
      required_style.remove(change_key);
    }
    else {
      required_style.set(change_key, change_value);
    }

    // Check if the style already exists
    var se = {exists:false, style_id:Globals.NOTHING, style:new Style()};
    se.exists = false;
    for (style_id in ed.styles.keys()) {
      var style = ed.styles.get(style_id);
      if (Util.mapSame(required_style, style)) {
        se.exists = true;
        se.style_id = style_id;
        break;
      }
    }
    if(!se.exists) {
      se.style = required_style;
    }
    return se;
  }


  public function style_new(style:Style) : StyleId {
    var style_id = style_id_make();
    ed._hx_create_style(style_id);
    for (change_type in style.keys()) {
      var change_value = style.get(change_type);
      ed._hx_modify_style(style_id, change_type, change_value);
    }
    ed.styles[style_id] = style;
    return style_id;
  }


  public function style_id_make() : StyleId {
    // TODO - O(n^2) ...
    return Util.unique_int([for (x in ed.styles.keys()) x]);
  }


  // Test if the cursor position encompasses a word
  // see module doc for more info
  public function word_start_get(row, col) {
    // row and col must be inside a word
    // TODO go up rows...
    var i = col;
    while (true) {
      if (is_word_start(row, i)) {
        return i;
      }
      i--;
    }
  }


  // Test if the cursor position encompasses a word
  // see module doc for more info
  public function word_end_get(row, col) {
    // row and col must be inside a word
    var i = col;
    while (true) {
      if (is_word_end(row, i)) {
        return i;
      }
      i++;
    }
  }


  public function is_word_extremity(row, col) : Bool {
    if (is_word_start(row, col)) {
      return true;
    }
    else if (is_word_end(row, col)) {
      return true;
    }
    return false;
  }


  // Test if the cursor position encompasses a word
  // see module doc for more info
  function is_word_start(row, col) {
    if (col == Globals.START_COL) {
      return true;
    }
    // TODO indexs must become addable, +1/-1 for row and col
    var char_prev = ed._hx_char_at_index(row, col-1);
    if (char_prev == ' ') {
      return true;
    }
    return false;
  }


  // Test if the cursor position encompasses a word
  // see module doc for more info
  function is_word_end(row, col) {
    // Need to specify this behvaior also for ed._hx_char_at_index
    // TODO indexs must become addable, +1/-1 for row and col
    var char = ed._hx_char_at_index(row, col);
    if (char != ' ' && char != '\n' && char != Globals.EOF) {
      return false;
    }
    return true;
  }


  // TODO - just make this a dynamic function?
  public function register_consumer(func) {
    consumers.push(func);
  }

  // TODO make this smarter and remove the reset
  // the consumer func will be passed an "apply_screen_update"
  // function, this function takes a param type function called event_handler
  // The event_handler needs to accept key,value pairs and handle resets
  public function consumer_run(row, col) {
    function _apply_screen_updates(event_handler) {
      event_handler("reset", "");
      var style_id = get_tag_of_next_char(row, col);
      var style = ed.styles.get(style_id);
      Assert.assert(ed.styles.exists(style_id));
      for (style_type in style.keys()) {
        var value = style.get(style_type);
        event_handler(style_type, value);
      }
    }
    for (updater in consumers) {
      updater(_apply_screen_updates);
    }
  }

}
