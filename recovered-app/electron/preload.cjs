const { contextBridge, ipcRenderer } = require("electron");
contextBridge.exposeInMainWorld("chmate", {
  platform: process.platform,
  defaults: () => ipcRenderer.invoke("boards:default"),
  menu: () => ipcRenderer.invoke("boards:menu"),
  threads: (board) => ipcRenderer.invoke("boards:threads", board),
  posts: (thread) => ipcRenderer.invoke("threads:posts", thread),
  post: (data) => ipcRenderer.invoke("posts:send", data),
  generate: (data) => ipcRenderer.invoke("ai:generate", data),
  capture: () => ipcRenderer.invoke("capture:save"),
  pickImage: (kind) => ipcRenderer.invoke("image:pick", kind),
  resolveImage: (url) => ipcRenderer.invoke("image:resolve", url),
  copyText: (value) => ipcRenderer.invoke("clipboard:write", value),
  setImageViewerOpen: (value) => ipcRenderer.invoke("viewer:set-open", value),
  onImageViewerClose: (callback) => {
    const listener = () => callback();
    ipcRenderer.on("viewer:request-close", listener);
    return () => ipcRenderer.removeListener("viewer:request-close", listener);
  },
  uploadImageViaWeb: (data) => ipcRenderer.invoke("image:upload-web", data),
  openExternal: (url) => ipcRenderer.invoke("external:open", url),
});
