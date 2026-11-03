/* ===============================================================
   REVISIONES — comentarios, historial, versiones y aprobaciones.

   Lo cargan index.html (estudio) y ver.html (cliente). Los datos viven
   en Supabase; cómo montarlo está en supabase/LEEME.md.

   Mientras url o anonKey estén vacíos, todo esto queda apagado y los
   visores funcionan como antes.
=============================================================== */
const REV_CONFIG={
  url:'',            // https://xxxxxxxx.supabase.co
  anonKey:'',        // Project Settings › API › anon public. Es pública por diseño.
  bucket:'adjuntos',
  maxMB:25,
  maxArchivos:10
};

const REV_CDN=[
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/dist/umd/supabase.js',
  'https://unpkg.com/@supabase/supabase-js@2.45.4/dist/umd/supabase.js'
];

const Rev={
  sb:null,

  activo(){ return !!(REV_CONFIG.url && REV_CONFIG.anonKey); },

  cargarScript(urls){
    return new Promise((resolve,reject)=>{
      let i=0;
      (function next(){
        if(i>=urls.length){ reject(new Error('No se ha podido cargar Supabase')); return; }
        const s=document.createElement('script');
        s.src=urls[i++]; s.onload=resolve; s.onerror=next;
        document.head.appendChild(s);
      })();
    });
  },

  async cliente(){
    if(this.sb) return this.sb;
    if(!window.supabase) await this.cargarScript(REV_CDN);
    this.sb=window.supabase.createClient(REV_CONFIG.url,REV_CONFIG.anonKey);
    return this.sb;
  },

  /* ---------------- adjuntos ---------------- */

  urlAdjunto(path){
    return REV_CONFIG.url+'/storage/v1/object/public/'+REV_CONFIG.bucket+'/'+
           String(path).split('/').map(encodeURIComponent).join('/');
  },

  /* Valida antes de subir nada: así no queda la mitad subida */
  revisarArchivos(files){
    if(files.length>REV_CONFIG.maxArchivos)
      throw new Error('Como máximo '+REV_CONFIG.maxArchivos+' archivos por mensaje.');
    const grandes=files.filter(f=>f.size>REV_CONFIG.maxMB*1024*1024);
    if(grandes.length)
      throw new Error('«'+grandes[0].name+'» pasa de '+REV_CONFIG.maxMB+' MB.');
  },

  /* El almacenamiento no acepta acentos ni espacios en la ruta */
  nombreSeguro(n){
    const limpio=String(n||'archivo').normalize('NFD').replace(/[̀-ͯ]/g,'')
      .replace(/[^A-Za-z0-9._-]+/g,'-').replace(/^-+|-+$/g,'');
    return (limpio||'archivo').slice(-80);
  },

  async subir(carpeta,file,nombreFijo){
    const sb=await this.cliente();
    const azar=Math.random().toString(36).slice(2,8);
    const path=carpeta+'/'+(nombreFijo||(Date.now().toString(36)+'-'+azar+'-'+this.nombreSeguro(file.name)));
    const {error}=await sb.storage.from(REV_CONFIG.bucket).upload(path,file,{
      contentType:file.type||'application/octet-stream',
      upsert:!!nombreFijo
    });
    if(error) throw new Error('No se ha podido subir «'+(file.name||'archivo')+'»: '+error.message);
    return {path, nombre:file.name||nombreFijo||'archivo', tipo:file.type||'', tam:file.size||0};
  },

  async subirVarios(carpeta,files,progreso){
    this.revisarArchivos(files);
    const salida=[];
    for(let i=0;i<files.length;i++){
      if(progreso) progreso(i,files.length,files[i]);
      salida.push(await this.subir(carpeta,files[i]));
    }
    return salida;
  },

  /* ---------------- formato ---------------- */

  esc(t){
    return String(t==null?'':t).replace(/[&<>"']/g,c=>(
      {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  },
  fecha(iso){
    const d=new Date(iso);
    return d.toLocaleDateString('es-ES',{day:'2-digit',month:'short',year:'numeric'})+
           ' · '+d.toLocaleTimeString('es-ES',{hour:'2-digit',minute:'2-digit'});
  },
  tam(n){
    if(!n) return '';
    if(n<1024*1024) return Math.max(1,Math.round(n/1024))+' KB';
    return (n/1024/1024).toFixed(1).replace('.',',')+' MB';
  },
  ext(nombre){
    const e=String(nombre||'').split('.').pop();
    return e&&e!==nombre ? e.slice(0,4).toUpperCase() : 'ARCHIVO';
  },

  /* ---------------- estado de un diseño ----------------
     Mira la versión vigente: si el cliente la aprobó, aprobado; si ha
     pedido cambios sobre ella, cambios; si no, en revisión. */
  estado(mensajes,version){
    version=version||1;
    const pendientes=mensajes.filter(m=>m.tipo==='comentario'&&m.estado==='pendiente').length;
    const deEsta=mensajes.filter(m=>m.version===version);
    const aprobada=deEsta.some(m=>m.tipo==='aprobado');
    const cambios=deEsta.some(m=>m.tipo==='comentario');
    if(aprobada) return {clave:'aprobado', texto:'Aprobado v'+version, pendientes};
    if(cambios)  return {clave:'cambios',  texto:'Cambios pedidos', pendientes};
    return {clave:'revision', texto:'En revisión', pendientes};
  },

  /* ---------------- hilo ----------------
     cont: elemento donde pintar.
     opciones.vista: 'cliente' | 'estudio'
     opciones.acciones(m): devuelve un elemento con botones, o null */
  pintarHilo(cont,mensajes,opciones){
    opciones=opciones||{};
    const yo=opciones.vista||'cliente';
    cont.innerHTML='';
    if(!mensajes.length){
      cont.innerHTML='<p class="revVacio">'+(yo==='cliente'
        ? 'Todavía no hay comentarios. Escribe lo que cambiarías y adjunta lo que haga falta.'
        : 'Sin mensajes todavía.')+'</p>';
      return;
    }
    mensajes.forEach(m=>{
      const div=document.createElement('div');
      div.className='revMsg '+m.autor+' '+m.tipo;

      let quien, que='';
      if(m.tipo==='version'){
        quien='Versión '+m.version+' publicada';
      }else if(m.autor==='estudio'){
        quien='RUMM';
      }else{
        quien=m.nombre||'Cliente';
      }
      if(m.tipo==='aprobado') que='Aprueba la versión '+m.version;

      let estado='';
      if(m.tipo==='comentario'&&m.estado){
        const txt={pendiente:'Pendiente',aceptado:'Aceptado',rechazado:'Rechazado'}[m.estado];
        estado='<span class="revEstado '+m.estado+'">'+txt+'</span>';
      }

      div.innerHTML=
        '<div class="revCab">'+
          '<span class="revQuien">'+this.esc(quien)+'</span>'+
          (m.tipo!=='version'?'<span class="revVer">v'+m.version+'</span>':'')+
          estado+
          '<span class="revFecha">'+this.fecha(m.creado)+'</span>'+
        '</div>'+
        (que?'<p class="revQue">'+this.esc(que)+'</p>':'')+
        (m.texto?'<p class="revTexto">'+this.esc(m.texto)+'</p>':'');

      if(m.adjuntos&&m.adjuntos.length){
        const adj=document.createElement('div');
        adj.className='revAdjs';
        m.adjuntos.forEach(a=>{
          const url=this.urlAdjunto(a.path);
          const el=document.createElement('a');
          el.href=url; el.target='_blank'; el.rel='noopener';
          if(/^image\//.test(a.tipo||'')){
            el.className='revImg';
            const img=document.createElement('img');
            img.src=url; img.alt=a.nombre||'';
            el.appendChild(img);
          }else{
            el.className='revArchivo';
            el.innerHTML='<b>'+this.esc(this.ext(a.nombre))+'</b>'+
                         '<span>'+this.esc(a.nombre)+'</span>'+
                         '<i>'+this.tam(a.tam)+'</i>';
          }
          adj.appendChild(el);
        });
        div.appendChild(adj);
      }

      if(m.tipo==='comentario'&&m.estado==='rechazado'&&m.motivo){
        const p=document.createElement('p');
        p.className='revMotivo';
        p.textContent='Motivo: '+m.motivo;
        div.appendChild(p);
      }
      if(m.tipo==='comentario'&&m.estado==='aceptado'&&m.motivo){
        const p=document.createElement('p');
        p.className='revMotivo';
        p.textContent='Nota: '+m.motivo;
        div.appendChild(p);
      }

      const acc=opciones.acciones?opciones.acciones(m):null;
      if(acc) div.appendChild(acc);
      cont.appendChild(div);
    });
  },

  /* Estilos del hilo, compartidos por los dos visores */
  css:`
    .revVacio{color:var(--muted);font-size:11px;margin:6px 0 0}
    .revMsg{border-top:1px solid var(--rule);padding:12px 0}
    .revMsg:first-child{border-top:none;padding-top:4px}
    .revMsg.estudio .revQuien{color:var(--accent)}
    .revMsg.version{background:var(--stage);padding:12px;margin:8px 0;border-top:none}
    .revMsg.aprobado .revQue{color:#2E7D4F;font-weight:700}
    .revCab{display:flex;align-items:baseline;gap:8px;flex-wrap:wrap}
    .revQuien{font-size:10px;letter-spacing:.14em;text-transform:uppercase;font-weight:700}
    .revVer{font-size:9px;letter-spacing:.1em;color:var(--muted);border:1px solid var(--rule);padding:0 4px}
    .revFecha{margin-left:auto;font-size:9px;letter-spacing:.08em;color:var(--muted)}
    .revEstado{font-size:9px;letter-spacing:.12em;text-transform:uppercase;padding:1px 6px}
    .revEstado.pendiente{background:#FFF2CC;color:#7A5C00}
    .revEstado.aceptado{background:#DDF2E4;color:#1F6B3D}
    .revEstado.rechazado{background:#FCE3DF;color:#A3321F}
    .revQue{margin:6px 0 0;font-size:12px}
    .revTexto{margin:6px 0 0;font-size:12px;white-space:pre-wrap;word-wrap:break-word}
    .revMotivo{margin:6px 0 0;font-size:11px;color:var(--muted);font-style:italic}
    .revAdjs{display:flex;flex-wrap:wrap;gap:6px;margin-top:8px}
    .revImg{display:block;width:84px;height:84px;background:var(--paper);border:1px solid var(--rule)}
    .revMsg.version .revImg{width:100%;height:auto;aspect-ratio:1/1;max-width:220px}
    .revImg img{width:100%;height:100%;object-fit:contain;display:block}
    .revArchivo{display:flex;align-items:center;gap:6px;max-width:100%;border:1px solid var(--rule);
      padding:5px 8px;font-size:11px;color:inherit;text-decoration:none;background:var(--paper)}
    .revArchivo:hover{border-color:var(--accent)}
    .revArchivo b{font-size:9px;letter-spacing:.08em;color:var(--accent)}
    .revArchivo span{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;min-width:0}
    .revArchivo i{font-style:normal;color:var(--muted);font-size:10px;flex:none}
    .revAcc{display:flex;gap:6px;margin-top:8px;flex-wrap:wrap}
    .revAcc button{background:none;border:1px solid var(--ink);padding:5px 10px;cursor:pointer;
      font-size:9px;letter-spacing:.14em;text-transform:uppercase}
    .revAcc button:hover{background:var(--ink);color:var(--paper)}
    .revAcc button.si{border-color:#1F6B3D;color:#1F6B3D}
    .revAcc button.si:hover{background:#1F6B3D;color:#fff}
    .revAcc button.no{border-color:#A3321F;color:#A3321F}
    .revAcc button.no:hover{background:#A3321F;color:#fff}
    .revAcc button.link{border:none;color:var(--muted);padding:5px 4px}
    .revAcc button.link:hover{background:none;color:var(--accent)}
    .revSello{display:inline-block;font-size:9px;letter-spacing:.12em;text-transform:uppercase;padding:2px 7px}
    .revSello.aprobado{background:#DDF2E4;color:#1F6B3D}
    .revSello.cambios{background:#FCE3DF;color:#A3321F}
    .revSello.revision{background:var(--stage);color:var(--muted)}
    .revElegidos{display:flex;flex-wrap:wrap;gap:6px;margin:0 0 8px}
    .revElegidos span{display:inline-flex;align-items:center;gap:4px;border:1px solid var(--rule);
      padding:3px 4px 3px 8px;font-size:10px;max-width:100%}
    .revElegidos span em{font-style:normal;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;max-width:180px}
    .revElegidos button{background:none;border:none;cursor:pointer;color:var(--muted);font-size:14px;line-height:1;padding:0 4px}
    .revElegidos button:hover{color:var(--accent)}
  `,
  ponerCss(){
    if(document.getElementById('revCss')) return;
    const st=document.createElement('style');
    st.id='revCss'; st.textContent=this.css;
    document.head.appendChild(st);
  },

  /* Lista de archivos elegidos con botón de quitar. Devuelve el array vivo. */
  selector(input,lista){
    const elegidos=[];
    const pintar=()=>{
      lista.innerHTML='';
      elegidos.forEach((f,i)=>{
        const s=document.createElement('span');
        s.innerHTML='<em></em><i></i><button type="button" aria-label="Quitar">&times;</button>';
        s.querySelector('em').textContent=f.name;
        s.querySelector('i').textContent=this.tam(f.size);
        s.querySelector('i').style.cssText='font-style:normal;color:var(--muted)';
        s.querySelector('button').onclick=()=>{ elegidos.splice(i,1); pintar(); };
        lista.appendChild(s);
      });
      lista.hidden=!elegidos.length;
    };
    input.addEventListener('change',()=>{
      Array.from(input.files||[]).forEach(f=>elegidos.push(f));
      input.value='';
      pintar();
    });
    elegidos.vaciar=()=>{ elegidos.length=0; pintar(); };
    elegidos.anadir=fs=>{ fs.forEach(f=>elegidos.push(f)); pintar(); };
    pintar();
    return elegidos;
  }
};
