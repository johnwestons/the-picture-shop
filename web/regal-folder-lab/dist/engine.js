/* Runs the test-page Lua rules with the vendored Fengari Lua VM. */
class FolderEngine {
  constructor(source) {
    const {lua, lauxlib, lualib, to_luastring}=fengari;
    this.lua=lua;this.str=to_luastring;this.L=lauxlib.luaL_newstate();
    lualib.luaL_openlibs(this.L);
    const program=`Folder=(function()\n${source}\nend)(); run=Folder.new()
      function benchAction(action) local accepted; run,accepted=Folder.dispatch(run,action); return accepted end
      function benchTick(dt) return Folder.update(run,dt) end`;
    if(lauxlib.luaL_loadstring(this.L,to_luastring(program))!==lua.LUA_OK) throw Error(lua.lua_tojsstring(this.L,-1));
    this.callLoaded(0,0);
  }
  callLoaded(args,results) {
    if(this.lua.lua_pcall(this.L,args,results,0)!==this.lua.LUA_OK) {
      const message=this.lua.lua_tojsstring(this.L,-1);this.lua.lua_pop(this.L,1);throw Error(message);
    }
  }
  invoke(name,value) {
    const l=this.lua,L=this.L;l.lua_getglobal(L,this.str(name));
    if(typeof value==='string')l.lua_pushstring(L,this.str(value));else l.lua_pushnumber(L,value);
    this.callLoaded(1,1);const result=l.lua_toboolean(L,-1);l.lua_pop(L,1);return result;
  }
  action(action){return this.invoke('benchAction',action);}
  tick(dt){return this.invoke('benchTick',dt);}
  state(){
    const l=this.lua,L=this.L;l.lua_getglobal(L,this.str('run'));const result={};
    l.lua_pushnil(L);
    while(l.lua_next(L,-2)){
      const key=l.lua_tojsstring(L,-2),type=l.lua_type(L,-1);
      if(type===l.LUA_TSTRING)result[key]=l.lua_tojsstring(L,-1);
      else if(type===l.LUA_TNUMBER)result[key]=l.lua_tonumber(L,-1);
      else if(type===l.LUA_TBOOLEAN)result[key]=l.lua_toboolean(L,-1);
      else if(key==='inTransit'){
        result.inTransit=[];for(let i=1;i<=l.lua_rawlen(L,-1);i++){
          l.lua_rawgeti(L,-1,i);result.inTransit.push(l.lua_tonumber(L,-1));l.lua_pop(L,1);
        }
      }
      l.lua_pop(L,1);
    }
    l.lua_pop(L,1);return result;
  }
}
globalThis.FolderEngine=FolderEngine;
