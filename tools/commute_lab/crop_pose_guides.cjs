// Mechanical lossless crops of the authoring diagram, never character artwork.
const fs=require('node:fs');
const path=require('node:path');
const zlib=require('node:zlib');
function crc(buffer){
    let c=0xffffffff;
    for(const b of buffer){c^=b;for(let j=0;j<8;j++)c=(c>>>1)^((c&1)?0xedb88320:0);}
    return (c^0xffffffff)>>>0;
}
function chunk(kind,data){
    const head=Buffer.alloc(8);head.writeUInt32BE(data.length);head.write(kind,4);
    const tail=Buffer.alloc(4);tail.writeUInt32BE(crc(Buffer.concat([Buffer.from(kind),data])));
    return Buffer.concat([head,data,tail]);
}
function cropGuides(root){
    const directory=path.join(root,'output/commute-rider-pose-guide');
    const input=fs.readFileSync(path.join(directory,'east-eight-phase-guide.png'));
    let ihdr, compressed=[];
    for(let offset=8;offset<input.length;){
        const size=input.readUInt32BE(offset),kind=input.toString('ascii',offset+4,offset+8);
        const data=input.subarray(offset+8,offset+8+size);
        if(kind==='IHDR')ihdr=Buffer.from(data);if(kind==='IDAT')compressed.push(data);
        offset+=size+12;
    }
    const width=ihdr.readUInt32BE(0),height=ihdr.readUInt32BE(4),bpp=ihdr[9]===2?3:4;
    if(ihdr[8]!==8||![2,6].includes(ihdr[9])||ihdr[12]!==0||width!==1024||height!==512)throw Error('Unexpected guide PNG format');
    const bytes=zlib.inflateSync(Buffer.concat(compressed)),stride=width*bpp;
    const pixels=Buffer.alloc(height*stride);
    for(let y=0;y<height;y++){
        const filter=bytes[y*(stride+1)];
        for(let x=0;x<stride;x++){
            const at=y*stride+x,a=x>=bpp?pixels[at-bpp]:0,b=y?pixels[at-stride]:0,c=y&&x>=bpp?pixels[at-stride-bpp]:0;
            let predictor=0;
            if(filter===1)predictor=a;if(filter===2)predictor=b;if(filter===3)predictor=(a+b)>>>1;
            if(filter===4){const p=a+b-c,pa=Math.abs(p-a),pb=Math.abs(p-b),pc=Math.abs(p-c);predictor=pa<=pb&&pa<=pc?a:pb<=pc?b:c;}
            if(filter>4)throw Error('Invalid PNG filter');
            pixels[at]=(bytes[y*(stride+1)+1+x]+predictor)&255;
        }
    }
    const names=['left-contact','left-down','right-passing','right-up','right-contact','right-down','left-passing','left-up'];
    for(let i=0;i<8;i++){
        const output=path.join(directory,'east-'+names[i]+'-guide-native.png');
        const rows=Buffer.alloc(256*(1+256*bpp));
        for(let y=0;y<256;y++){
            const start=((Math.floor(i/4)*256+y)*width+(i%4)*256)*bpp;
            pixels.copy(rows,y*(1+256*bpp)+1,start,start+256*bpp);
        }
        const header=Buffer.from(ihdr);header.writeUInt32BE(256,0);header.writeUInt32BE(256,4);
        fs.writeFileSync(output,Buffer.concat([input.subarray(0,8),chunk('IHDR',header),chunk('IDAT',zlib.deflateSync(rows)),chunk('IEND',Buffer.alloc(0))]));
    }
    return names.map(n=>path.join(directory,'east-'+n+'-guide-native.png'));
}
module.exports=cropGuides;
if(require.main===module) console.log(cropGuides(path.resolve(__dirname,'../..')).join('\n'));
