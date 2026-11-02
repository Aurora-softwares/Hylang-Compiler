// Linux-only native GTK4 application entry point generated/built by Hydrogen.
// This is an application executable, not a separately installed hyui host.
// Until the final in-process ABI milestone it runs compiled Hydrogen handlers
// through a private backend executable in <app>.runtime/app.
#include <gtk/gtk.h>
#include <gio/gio.h>
#include <glib/gstdio.h>
#include <algorithm>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>
#include <unistd.h>

namespace fs = std::filesystem;
struct Node {
    std::string tag;
    std::map<std::string, std::string> attrs;
    std::vector<std::unique_ptr<Node>> children;
};
static std::string attr(const Node* n, const char* key, const std::string& fallback="") {
    auto it=n->attrs.find(key);
    return it==n->attrs.end()?fallback:it->second;
}
static int number(const std::string& s, int fallback=0) {
    try { return s.empty()?fallback:std::stoi(s); } catch (...) { return fallback; }
}
static bool truth(const std::string& s) { return s=="true"; }
static std::vector<std::string> parts(const std::string& s, char sep) {
    std::vector<std::string> result; std::istringstream in(s); std::string x;
    while (std::getline(in,x,sep)) result.push_back(x);
    return result;
}
static std::string escapeJson(const std::string& s) {
    std::string out;
    for(unsigned char ch:s) {
        if(ch=='"' || ch=='\\') { out+='\\';out+=char(ch); }
        else if(ch=='\n') out+="\\n";
        else if(ch=='\r') out+="\\r";
        else if(ch=='\t') out+="\\t";
        else if(ch<32) out+="?";
        else out+=char(ch);
    }
    return out;
}
static std::string decode(std::string s) {
    // Reverse percent transport in the same order as Hydrogen's Bridge.
    for(auto p:{{"%09","\t"},{"%0D","\r"},{"%0A","\n"},{"%25","%"}}) {
        std::size_t at=0;
        while((at=s.find(p.first,at))!=std::string::npos) {s.replace(at,3,p.second);at+=std::strlen(p.second);}
    }
    return s;
}
struct Parser {
    std::unique_ptr<Node> root;
    std::vector<Node*> stack;
    static void open(GMarkupParseContext*,const gchar* name,const gchar** keys,
                     const gchar** values,gpointer data,GError**) {
        auto* self=static_cast<Parser*>(data);
        auto n=std::make_unique<Node>();n->tag=name;
        for(int i=0;keys && keys[i];++i)n->attrs[keys[i]]=values[i];
        Node* ref=n.get();
        if(self->stack.empty()) {
            if(self->root) return;
            self->root=std::move(n);
        } else self->stack.back()->children.push_back(std::move(n));
        self->stack.push_back(ref);
    }
    static void close(GMarkupParseContext*,const gchar*,gpointer data,GError**) {
        auto* self=static_cast<Parser*>(data);
        if(!self->stack.empty()) self->stack.pop_back();
    }
    void parse(const std::string& xml) {
        if(xml.size()>1048576) throw std::runtime_error("HYUI document exceeds 1 MiB");
        GMarkupParser p={open,close,nullptr,nullptr,nullptr};
        GMarkupParseContext* ctx=g_markup_parse_context_new(&p,G_MARKUP_TREAT_CDATA_AS_TEXT,this,nullptr);
        GError* error=nullptr;
        bool ok=g_markup_parse_context_parse(ctx,xml.data(),xml.size(),&error);
        if(ok) ok=g_markup_parse_context_end_parse(ctx,&error);
        if(!ok) {
            std::string message=error?error->message:"invalid UI markup";
            if(error)g_error_free(error);
            g_markup_parse_context_free(ctx);
            throw std::runtime_error(message);
        }
        g_markup_parse_context_free(ctx);
        if(!root || root->tag!="Window" || attr(root.get(),"version")!="1")
            throw std::runtime_error("HYUI requires a Window version=\"1\" root");
    }
};
struct App;
struct Hook { App* app; Node* node; std::string handler; int index=-1; };
struct Control { Node* node; GtkWidget* widget; std::string kind; };
struct App {
    fs::path folder, backend;
    Parser document;
    GtkApplication* application=nullptr;
    GtkWidget* window=nullptr;
    std::map<std::string,Control> controls;
    std::map<std::string,std::string> state;
    std::vector<std::unique_ptr<Hook>> hooks;
    std::string statePath,eventRequest;
    bool applying=false;
    int generatedId=0;
    explicit App(fs::path directory):folder(std::move(directory)),backend(folder/"__hyui_backend") {}
    std::string id(Node* n) {
        std::string key=attr(n,"id");
        if(key.empty()) { key="_hyui"+std::to_string(++generatedId);n->attrs["id"]=key; }
        return key;
    }
    void registerControl(Node* n,GtkWidget* widget,const char* kind) {
        auto name=id(n);
        controls[name]={n,widget,kind};
        for(auto key:{"text","value","checked","enabled","visible","running","open","path"}) {
            if(n->attrs.count(key)) state[name+"."+key]=attr(n,key);
        }
        if(!n->attrs.count("visible"))state[name+".visible"]="true";
        if(!n->attrs.count("enabled"))state[name+".enabled"]="true";
        if(widget) {
            gtk_widget_set_visible(widget,!n->attrs.count("visible")||truth(attr(n,"visible")));
            gtk_widget_set_sensitive(widget,!n->attrs.count("enabled")||truth(attr(n,"enabled")));
            auto tip=attr(n,"tooltip");
            if(!tip.empty())gtk_widget_set_tooltip_text(widget,tip.c_str());
            auto accessible=attr(n,"accessibleName");
            if(!accessible.empty())gtk_accessible_update_property(GTK_ACCESSIBLE(widget),
                GTK_ACCESSIBLE_PROPERTY_LABEL,accessible.c_str(),-1);
        }
    }
    Hook* hook(Node* n,const char* key) {
        auto handler=attr(n,key);
        if(handler.empty())return nullptr;
        auto item=std::make_unique<Hook>();
        item->app=this;item->node=n;item->handler=handler;
        auto* result=item.get();hooks.push_back(std::move(item));return result;
    }
    static void clicked(GtkWidget*,gpointer data) {
        auto* h=static_cast<Hook*>(data);
        if(!h->app->applying)h->app->dispatch(h->handler,h->app->id(h->node));
    }
    static void changed(GObject*,GParamSpec*,gpointer data) { clicked(nullptr,data); }
    static void changedSimple(GtkWidget*,gpointer data) { clicked(nullptr,data); }
    static void listSelected(GtkListBox*,GtkListBoxRow*,gpointer data) { clicked(nullptr,data); }
    static void switchChanged(GObject*,GParamSpec*,gpointer data) { clicked(nullptr,data); }
    static void radioToggled(GtkCheckButton* button,gpointer data) {
        auto* h=static_cast<Hook*>(data);
        if(!gtk_check_button_get_active(button)||h->app->applying)return;
        auto key=h->app->id(h->node);
        h->app->state[key+".value"]=std::to_string(h->index);
        h->app->dispatch(h->handler,key);
    }
    void bind(GtkWidget* widget,const char* signal,Node* n,const char* handler) {
        if(auto* h=hook(n,handler)) {
            std::string kind=signal;
            if(kind=="row-selected")
                g_signal_connect(widget,signal,G_CALLBACK(listSelected),h);
            else if(kind.compare(0,8,"notify::")==0)
                g_signal_connect(widget,signal,G_CALLBACK(changed),h);
            else g_signal_connect(widget,signal,G_CALLBACK(changedSimple),h);
        }
    }
    std::string value(const Control& c) {
        auto* w=c.widget;
        if(!w)return state[id(c.node)+".value"];
        auto tag=c.node->tag;
        if(tag=="Input"||tag=="SearchInput"||tag=="PasswordInput")return gtk_editable_get_text(GTK_EDITABLE(w));
        if(tag=="TextArea") {
            GtkTextIter a,b;auto* buffer=gtk_text_view_get_buffer(GTK_TEXT_VIEW(w));
            gtk_text_buffer_get_bounds(buffer,&a,&b);
            gchar* str=gtk_text_buffer_get_text(buffer,&a,&b,FALSE);
            std::string result=str?str:"";g_free(str);return result;
        }
        if(tag=="Slider")return std::to_string(int(gtk_range_get_value(GTK_RANGE(w))));
        if(tag=="NumberInput")return std::to_string(gtk_spin_button_get_value_as_int(GTK_SPIN_BUTTON(w)));
        if(tag=="CheckBox")return gtk_check_button_get_active(GTK_CHECK_BUTTON(w))?"true":"false";
        if(tag=="Switch")return gtk_switch_get_active(GTK_SWITCH(w))?"true":"false";
        if(tag=="Select")return std::to_string(gtk_drop_down_get_selected(GTK_DROP_DOWN(w)));
        if(tag=="ListBox"||tag=="Table") {
            auto* row=gtk_list_box_get_selected_row(GTK_LIST_BOX(w));
            return std::to_string(row?gtk_list_box_row_get_index(row):0);
        }
        if(tag=="Tabs") {
            std::string visible=gtk_stack_get_visible_child_name(GTK_STACK(w));
            int count=0;
            for(auto& child:c.node->children) {
                if(id(child.get())==visible)return std::to_string(count);
                ++count;
            }
            return "0";
        }
        if(tag=="RadioGroup")return state[id(c.node)+".value"];
        return state[id(c.node)+".value"];
    }
    void snapshot() {
        for(auto& [name,c]:controls) {
            std::string prop;
            const auto& tag=c.node->tag;
            if(tag=="Input"||tag=="SearchInput"||tag=="TextArea") prop="text";
            else if(tag=="PasswordInput")continue;
            else if(tag=="CheckBox"||tag=="Switch")prop="checked";
            else if(tag=="Select"||tag=="ListBox"||tag=="Table"||tag=="Slider"||
                    tag=="NumberInput"||tag=="Tabs"||tag=="RadioGroup")prop="value";
            if(!prop.empty())state[name+"."+prop]=value(c);
        }
    }
    bool execute(const std::vector<std::string>& args,std::string& stdoutText) {
        GSubprocessLauncher* launcher=g_subprocess_launcher_new(
            GSubprocessFlags(G_SUBPROCESS_FLAGS_STDOUT_PIPE|G_SUBPROCESS_FLAGS_STDERR_PIPE));
        g_subprocess_launcher_set_cwd(launcher,folder.c_str());
        std::vector<const char*> argv;
        argv.push_back(backend.c_str());
        for(auto& a:args)argv.push_back(a.c_str());
        argv.push_back(nullptr);
        GError* error=nullptr;
        GSubprocess* proc=g_subprocess_launcher_spawnv(launcher,argv.data(),&error);
        g_object_unref(launcher);
        if(!proc) {
            std::cerr<<"Hydrogen UI backend cannot start: "<<(error?error->message:"unknown")<<"\n";
            if(error)g_error_free(error);
            return false;
        }
        gchar *out=nullptr,*err=nullptr;
        bool ok=g_subprocess_communicate_utf8(proc,nullptr,nullptr,&out,&err,&error);
        if(ok)ok=g_subprocess_get_successful(proc);
        if(!ok)std::cerr<<"Hydrogen UI backend failed: "<<(err?err:(error?error->message:"unknown"))<<"\n";
        stdoutText=out?out:"";
        g_free(out);g_free(err);
        if(error)g_error_free(error);
        g_object_unref(proc);
        return ok;
    }
    void apply(const std::string& output) {
        applying=true;
        for(auto& line:parts(output,'\n')) {
            if(line.compare(0,5,"HYUI\t")!=0)continue;
            auto fields=parts(line,'\t');
            if(fields.size()!=5 || fields[1]!="SET")continue;
            const std::string name=decode(fields[2]),prop=decode(fields[3]),v=decode(fields[4]);
            auto it=controls.find(name);
            if(it==controls.end())continue;
            Node* n=it->second.node;GtkWidget* w=it->second.widget;
            state[name+"."+prop]=v;
            if(prop=="visible" && w)gtk_widget_set_visible(w,truth(v));
            else if(prop=="enabled" && w)gtk_widget_set_sensitive(w,truth(v));
            else if(prop=="text" && w) {
                if(n->tag=="Label")gtk_label_set_text(GTK_LABEL(w),v.c_str());
                else if(n->tag=="Input"||n->tag=="SearchInput")gtk_editable_set_text(GTK_EDITABLE(w),v.c_str());
            } else if(prop=="checked" && w) {
                if(n->tag=="CheckBox")gtk_check_button_set_active(GTK_CHECK_BUTTON(w),truth(v));
                if(n->tag=="Switch")gtk_switch_set_active(GTK_SWITCH(w),truth(v));
            } else if(prop=="value" && w) {
                if(n->tag=="ProgressBar")
                    gtk_progress_bar_set_fraction(GTK_PROGRESS_BAR(w),std::clamp(number(v)/100.0,0.0,1.0));
                if(n->tag=="Slider")gtk_range_set_value(GTK_RANGE(w),number(v));
                if(n->tag=="NumberInput")gtk_spin_button_set_value(GTK_SPIN_BUTTON(w),number(v));
                if(n->tag=="Select")gtk_drop_down_set_selected(GTK_DROP_DOWN(w),number(v));
                if(n->tag=="RadioGroup") {
                    int index=0;
                    for(GtkWidget* child=gtk_widget_get_first_child(w);child;
                        child=gtk_widget_get_next_sibling(child)) {
                        if(index==number(v))gtk_check_button_set_active(GTK_CHECK_BUTTON(child),TRUE);
                        ++index;
                    }
                }
                if(n->tag=="ListBox"||n->tag=="Table") {
                    gtk_list_box_select_row(GTK_LIST_BOX(w),
                        gtk_list_box_get_row_at_index(GTK_LIST_BOX(w),number(v)));
                }
                if(n->tag=="Tabs" && number(v)>=0 && number(v)<int(n->children.size()))
                    gtk_stack_set_visible_child_name(GTK_STACK(w),id(n->children[number(v)].get()).c_str());
            } else if(prop=="running" && w && n->tag=="Spinner") {
                if(truth(v))gtk_spinner_start(GTK_SPINNER(w));
                else gtk_spinner_stop(GTK_SPINNER(w));
            }
        }
        applying=false;
    }
    void dispatch(const std::string& handler,const std::string& sender) {
        if(handler.empty()||handler.size()>128)return;
        snapshot();
        std::vector<std::string> args={"--hyui-event",handler,sender};
        std::size_t bytes=0;
        for(auto& [name,c]:controls) {
            const auto& tag=c.node->tag;
            if(tag=="PasswordInput"||tag=="Clipboard")continue;
            std::string prop;
            if(tag=="Input"||tag=="SearchInput"||tag=="TextArea"||tag=="Label")prop="text";
            else if(tag=="CheckBox"||tag=="Switch")prop="checked";
            else if(tag=="Select"||tag=="ListBox"||tag=="Table"||tag=="Slider"||
                tag=="NumberInput"||tag=="Tabs"||tag=="RadioGroup"||tag=="ProgressBar")prop="value";
            if(prop.empty())continue;
            auto val=state[name+"."+prop];
            bytes+=name.size()+val.size()+6;
            if(bytes>24000){std::cerr<<"HYUI event snapshot is too large\n";return;}
            args.push_back(name);args.push_back(val);
        }
        std::string response;
        if(execute(args,response))apply(response);
    }
    static void append(GtkWidget* parent,GtkWidget* child,const Node* parentNode=nullptr,const Node* childNode=nullptr) {
        if(!child || !parent)return;
        if(GTK_IS_STACK(parent)) {
            gtk_stack_add_titled(GTK_STACK(parent),child,attr(childNode,"id").c_str(),
                                 attr(childNode,"title","Page").c_str());
        } else if(GTK_IS_GRID(parent)) {
            int cols=std::max(1,number(attr(parentNode,"columns"),2));
            int index=0;
            for(GtkWidget* existing=gtk_widget_get_first_child(parent);
                existing;existing=gtk_widget_get_next_sibling(existing))++index;
            gtk_grid_attach(GTK_GRID(parent),child,index%cols,index/cols,1,1);
        } else if(GTK_IS_BOX(parent)) gtk_box_append(GTK_BOX(parent),child);
        else if(GTK_IS_SCROLLED_WINDOW(parent))gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(parent),child);
    }
    GtkWidget* build(Node* n) {
        const auto& tag=n->tag;
        GtkWidget *w=nullptr,*container=nullptr;
        if(tag=="ColumnPanel"||tag=="RowPanel"||tag=="Toolbar"||tag=="Tab"||tag=="GridPanel") {
            if(tag=="GridPanel") {
                w=gtk_grid_new();gtk_grid_set_row_spacing(GTK_GRID(w),number(attr(n,"gap"),8));
                gtk_grid_set_column_spacing(GTK_GRID(w),number(attr(n,"gap"),8));
            } else {
                bool horizontal=tag=="RowPanel"||tag=="Toolbar";
                w=gtk_box_new(horizontal?GTK_ORIENTATION_HORIZONTAL:GTK_ORIENTATION_VERTICAL,number(attr(n,"gap"),8));
            }
            container=w;
        } else if(tag=="Panel") {
            w=gtk_frame_new(attr(n,"title").empty()?nullptr:attr(n,"title").c_str());
            container=gtk_box_new(GTK_ORIENTATION_VERTICAL,number(attr(n,"gap"),8));
            gtk_widget_set_margin_start(container,number(attr(n,"padding"),12));
            gtk_widget_set_margin_end(container,number(attr(n,"padding"),12));
            gtk_widget_set_margin_top(container,number(attr(n,"padding"),12));
            gtk_widget_set_margin_bottom(container,number(attr(n,"padding"),12));
            gtk_frame_set_child(GTK_FRAME(w),container);
        } else if(tag=="ScrollView") {
            w=gtk_scrolled_window_new();
            container=gtk_box_new(GTK_ORIENTATION_VERTICAL,number(attr(n,"gap"),6));
            gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(w),container);
            gtk_widget_set_size_request(w,-1,number(attr(n,"height"),150));
        } else if(tag=="Tabs") {
            w=gtk_stack_new();
            gtk_stack_set_transition_type(GTK_STACK(w),GTK_STACK_TRANSITION_TYPE_SLIDE_LEFT_RIGHT);
            auto* wrapper=gtk_box_new(GTK_ORIENTATION_VERTICAL,6);
            auto* switcher=gtk_stack_switcher_new();
            gtk_stack_switcher_set_stack(GTK_STACK_SWITCHER(switcher),GTK_STACK(w));
            gtk_box_append(GTK_BOX(wrapper),switcher);
            gtk_box_append(GTK_BOX(wrapper),w);
            registerControl(n,w,"Tabs");
            for(auto& ch:n->children)append(w,build(ch.get()),n,ch.get());
            int initial=number(attr(n,"value"));
            if(initial>=0 && initial<int(n->children.size()))
                gtk_stack_set_visible_child_name(GTK_STACK(w),id(n->children[initial].get()).c_str());
            if(auto* h=hook(n,"onChange"))
                g_signal_connect(w,"notify::visible-child-name",G_CALLBACK(changed),h);
            return wrapper;
        } else if(tag=="Label") {
            w=gtk_label_new(attr(n,"text").c_str());
            gtk_label_set_wrap(GTK_LABEL(w),TRUE);
            gtk_label_set_xalign(GTK_LABEL(w),0);
            auto role=attr(n,"role");
            if(role=="title")gtk_widget_add_css_class(w,"title-1");
            if(role=="heading")gtk_widget_add_css_class(w,"heading");
            if(attr(n,"tone")=="muted")gtk_widget_add_css_class(w,"dim-label");
        } else if(tag=="Button"||tag=="ToolButton"||tag=="MenuItem") {
            w=gtk_button_new_with_label(attr(n,"text").c_str());
            if(truth(attr(n,"primary")))gtk_widget_add_css_class(w,"suggested-action");
            bind(w,"clicked",n,"onClick");
        } else if(tag=="Input"||tag=="SearchInput"||tag=="PasswordInput") {
            w=tag=="SearchInput"?gtk_search_entry_new():gtk_entry_new();
            gtk_editable_set_text(GTK_EDITABLE(w),attr(n,"text").c_str());
            if(tag=="PasswordInput")gtk_entry_set_visibility(GTK_ENTRY(w),FALSE);
            gtk_entry_set_placeholder_text(GTK_ENTRY(w),attr(n,"placeholder").c_str());
            bind(w,"changed",n,"onChange");
            bind(w,"activate",n,"onSubmit");
        } else if(tag=="TextArea") {
            w=gtk_text_view_new();
            gtk_text_view_set_wrap_mode(GTK_TEXT_VIEW(w),GTK_WRAP_WORD_CHAR);
            auto* buffer=gtk_text_view_get_buffer(GTK_TEXT_VIEW(w));
            gtk_text_buffer_set_text(buffer,attr(n,"text").c_str(),-1);
            gtk_widget_set_size_request(w,-1,number(attr(n,"height"),80));
        } else if(tag=="CheckBox") {
            w=gtk_check_button_new_with_label(attr(n,"text").c_str());
            gtk_check_button_set_active(GTK_CHECK_BUTTON(w),truth(attr(n,"checked")));
            bind(w,"toggled",n,"onChange");
        } else if(tag=="Switch") {
            auto* row=gtk_box_new(GTK_ORIENTATION_HORIZONTAL,8);
            auto* label=gtk_label_new(attr(n,"text").c_str());
            gtk_box_append(GTK_BOX(row),label);
            w=gtk_switch_new();
            gtk_switch_set_active(GTK_SWITCH(w),truth(attr(n,"checked")));
            gtk_box_append(GTK_BOX(row),w);
            registerControl(n,w,"Switch");
            bind(w,"notify::active",n,"onChange");
            return row;
        } else if(tag=="Slider") {
            w=gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL,number(attr(n,"minimum")),number(attr(n,"maximum"),100),1);
            gtk_range_set_value(GTK_RANGE(w),number(attr(n,"value")));
            bind(w,"value-changed",n,"onChange");
        } else if(tag=="NumberInput") {
            w=gtk_spin_button_new_with_range(number(attr(n,"minimum")),number(attr(n,"maximum"),100),1);
            gtk_spin_button_set_value(GTK_SPIN_BUTTON(w),number(attr(n,"value")));
            bind(w,"value-changed",n,"onChange");
        } else if(tag=="Select") {
            auto options=parts(attr(n,"items"),'|');
            std::vector<const char*> names;
            for(auto& a:options)names.push_back(a.c_str());
            names.push_back(nullptr);
            w=gtk_drop_down_new_from_strings(names.data());
            gtk_drop_down_set_selected(GTK_DROP_DOWN(w),number(attr(n,"value")));
            if(auto* h=hook(n,"onChange"))
                g_signal_connect(w,"notify::selected",G_CALLBACK(changed),h);
        } else if(tag=="ProgressBar") {
            w=gtk_progress_bar_new();
            gtk_progress_bar_set_fraction(GTK_PROGRESS_BAR(w),std::clamp(number(attr(n,"value"))/100.0,0.0,1.0));
        } else if(tag=="Spinner") {
            w=gtk_spinner_new();
            if(truth(attr(n,"running")))gtk_spinner_start(GTK_SPINNER(w));
        } else if(tag=="Separator")w=gtk_separator_new(GTK_ORIENTATION_HORIZONTAL);
        else if(tag=="Spacer") {w=gtk_box_new(GTK_ORIENTATION_VERTICAL,0);gtk_widget_set_size_request(w,1,number(attr(n,"height"),12));}
        else if(tag=="Image") {
            fs::path source=folder/attr(n,"source");
            w=gtk_picture_new_for_filename(source.c_str());
            gtk_widget_set_size_request(w,-1,number(attr(n,"height"),80));
        } else if(tag=="ListBox"||tag=="Table") {
            auto* view=gtk_list_box_new();
            std::vector<std::string> entries=parts(attr(n,tag=="Table"?"rows":"items"),tag=="Table"?'\n':'|');
            for(auto& entry:entries) {
                auto* row=gtk_label_new(entry.c_str());gtk_label_set_xalign(GTK_LABEL(row),0);
                gtk_list_box_append(GTK_LIST_BOX(view),row);
            }
            gtk_list_box_select_row(GTK_LIST_BOX(view),
                gtk_list_box_get_row_at_index(GTK_LIST_BOX(view),number(attr(n,"value"))));
            bind(view,"row-selected",n,"onChange");
            w=view;
            gtk_widget_set_size_request(w,-1,number(attr(n,"height"),120));
        } else if(tag=="RadioGroup") {
            auto* box=gtk_box_new(GTK_ORIENTATION_VERTICAL,4);
            GtkCheckButton* previous=nullptr;
            auto entries=parts(attr(n,"items"),'|');
            int i=0;
            for(auto& entry:entries) {
                auto* button=GTK_CHECK_BUTTON(gtk_check_button_new_with_label(entry.c_str()));
                if(previous)gtk_check_button_set_group(button,previous);
                if(i==number(attr(n,"value")))gtk_check_button_set_active(button,TRUE);
                gtk_box_append(GTK_BOX(box),GTK_WIDGET(button));
                if(auto* h=hook(n,"onChange")) {
                    h->index=i;
                    g_signal_connect(button,"toggled",G_CALLBACK(radioToggled),h);
                }
                previous=button;++i;
            }
            w=box;
        } else if(tag=="MenuBar") {
            w=gtk_box_new(GTK_ORIENTATION_HORIZONTAL,6);
            for(auto& child:n->children) {
                auto* button=gtk_menu_button_new();
                gtk_menu_button_set_label(GTK_MENU_BUTTON(button),attr(child.get(),"text").c_str());
                auto* pop=gtk_popover_new();
                auto* items=gtk_box_new(GTK_ORIENTATION_VERTICAL,3);
                for(auto& item:child->children)
                    append(items,build(item.get()),child.get(),item.get());
                gtk_popover_set_child(GTK_POPOVER(pop),items);
                gtk_menu_button_set_popover(GTK_MENU_BUTTON(button),pop);
                gtk_box_append(GTK_BOX(w),button);
            }
            registerControl(n,w,"MenuBar");
            return w;
        } else if(tag=="Menu"||tag=="ContextMenu"||tag=="Popover"||tag=="Clipboard"||tag=="Dialog"||tag=="State"||tag=="Timer") {
            registerControl(n,nullptr,tag.c_str());
            return nullptr;
        } else {
            throw std::runtime_error("GTK4 direct frontend does not support HYUI element: "+tag);
        }
        registerControl(n,w,tag.c_str());
        if(container)for(auto& child:n->children)append(container,build(child.get()),n,child.get());
        if(w && truth(attr(n,"fill")))gtk_widget_set_hexpand(w,TRUE);
        if(w && number(attr(n,"preferredWidth"))>0)gtk_widget_set_size_request(w,number(attr(n,"preferredWidth")),-1);
        return w;
    }
    static gboolean tick(gpointer data) {
        auto* h=static_cast<Hook*>(data);
        if(truth(h->app->state[h->app->id(h->node)+".running"]))
            h->app->dispatch(h->handler,h->app->id(h->node));
        return G_SOURCE_CONTINUE;
    }
    static gboolean scripted(gpointer data) {
        auto* self=static_cast<App*>(data);
        if(!self->eventRequest.empty()) {
            auto i=self->eventRequest.find(':');
            if(i!=std::string::npos)self->dispatch(self->eventRequest.substr(0,i),self->eventRequest.substr(i+1));
        }
        if(!self->statePath.empty()) {
            self->snapshot();
            std::ofstream out(self->statePath);
            out<<"{";
            bool first=true;
            for(auto& [key,value]:self->state) {
                if(!first)out<<",";
                first=false;
                out<<"\""<<escapeJson(key)<<"\":";
                if(value=="true"||value=="false")out<<value;
                else if(key.size()>6&&key.compare(key.size()-6,6,".value")==0 &&
                    value.find_first_not_of("0123456789")==std::string::npos&&!value.empty())out<<value;
                else out<<"\""<<escapeJson(value)<<"\"";
            }
            out<<"}\n";
            g_application_quit(G_APPLICATION(self->application));
        }
        return G_SOURCE_REMOVE;
    }
    void activate(GtkApplication* gtkApp) {
        window=gtk_application_window_new(gtkApp);
        const auto* n=document.root.get();
        gtk_window_set_title(GTK_WINDOW(window),attr(n,"title","Hydrogen").c_str());
        gtk_window_set_default_size(GTK_WINDOW(window),number(attr(n,"width"),1100),number(attr(n,"height"),820));
        auto* body=gtk_box_new(GTK_ORIENTATION_VERTICAL,10);
        gtk_widget_set_margin_start(body,14);gtk_widget_set_margin_end(body,14);
        gtk_widget_set_margin_top(body,14);gtk_widget_set_margin_bottom(body,14);
        auto* scroll=gtk_scrolled_window_new();
        gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroll),body);
        gtk_window_set_child(GTK_WINDOW(window),scroll);
        for(auto& child:document.root->children)
            append(body,build(child.get()),n,child.get());
        gtk_window_present(GTK_WINDOW(window));
        for(auto& [name,c]:controls) {
            if(c.node->tag=="Timer") {
                if(auto* h=hook(c.node,"onTick"))
                    g_timeout_add(std::max(100,number(attr(c.node,"interval"),350)),tick,h);
            }
        }
        if(!attr(n,"onLoad").empty())dispatch(attr(n,"onLoad"),id(document.root.get()));
        if(!statePath.empty()||!eventRequest.empty())g_timeout_add(300,scripted,this);
    }
    static void activated(GApplication* app,gpointer data) {
        static_cast<App*>(data)->activate(GTK_APPLICATION(app));
    }
    int run(int argc,char** argv) {
        std::string content;
        std::ifstream view(folder/"__hyui_document");
        std::string doc;
        if(!std::getline(view,doc)||doc.empty()||doc[0]=='/'||
           doc.find("..")!=std::string::npos||doc.find('\\')!=std::string::npos)
            throw std::runtime_error("invalid packaged HYUI document path");
        std::ifstream in(folder/doc,std::ios::binary);
        if(!in)throw std::runtime_error("cannot read packaged HYUI document");
        content.assign(std::istreambuf_iterator<char>(in),{});
        document.parse(content);
        for(int i=1;i<argc;++i) {
            std::string arg=argv[i];
            if(arg=="--state-output"&&i+1<argc)statePath=argv[++i];
            else if(arg=="--event"&&i+1<argc)eventRequest=argv[++i];
            else if(arg=="--help") {
                std::cout<<"Hydrogen native GTK4 application (--event handler:sender --state-output path)\n";
                return 0;
            } else throw std::runtime_error("unsupported direct GTK4 argument: "+arg);
        }
        std::string initial;
        if(!execute({},initial))return 1;
        application=gtk_application_new("software.aurora.HydrogenNativeGTK",G_APPLICATION_DEFAULT_FLAGS);
        g_signal_connect(application,"activate",G_CALLBACK(activated),this);
        // The compiled application owns its GTK event loop; the native UI host
        // and launcher are not executed or required.
        char* appArgv[]={argv[0],nullptr};
        int result=g_application_run(G_APPLICATION(application),1,appArgv);
        g_object_unref(application);return result;
    }
};
int main(int argc,char** argv) {
    try {
        std::string executable(8192,'\0');
        ssize_t len=readlink("/proc/self/exe",executable.data(),executable.size()-1);
        if(len<=0)throw std::runtime_error("cannot resolve GTK4 application executable");
        executable.resize(len);
        fs::path folder=executable+".runtime";
        folder/="app";
        App app(folder);
        return app.run(argc,argv);
    } catch(const std::exception& e) {
        std::cerr<<"Hydrogen GTK4: "<<e.what()<<"\n";
        return 1;
    }
}
