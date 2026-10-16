#!/usr/bin/env python3
# Modelo analítico de balance: valor por coste de cada perfil (1,00 = equilibrado).
# Uso: python3 tool/balance_model.py data/units.json
# Es una primera aproximación; confírmalo con: dart run bin/simulate.dart duelos
import json,sys
U={p['id']:p for p in json.load(open(sys.argv[1]))['profiles']}
def p_succ(t, mod=0):
    return sum(1 for r in range(1,7) if r!=1 and (r==6 or r+mod>=t))/6
def wound_t(f,res):
    if f>=2*res: return 2
    if f>res: return 3
    if f==res: return 4
    if f*2<=res: return 6
    return 5
def kills(att, w, dfn, n_att=None, auto=False, fbonus=0, hitmod=0):
    n=n_att if n_att is not None else att['soldados']
    dice=n*w['a']
    hit = 1.0 if auto else p_succ(w.get('impacta') or att['stats']['pun'], hitmod)
    wd = p_succ(wound_t(w['f']+fbonus, dfn['stats']['res']))
    st = dfn['stats']['sal']+w['pa']; ps = 0 if st>6 else p_succ(st)
    return min(dice*hit*wd*(1-ps)*min(1, w['d']/dfn['stats']['her']), dfn['soldados'])
ids=[i for i in U if i!='capitana']
def ranged(A): return next((w for w in A['armas'] if w['alcance']>0),None)
def melee(A): return next((w for w in A['armas'] if w['alcance']==0),{'impacta':5,'a':1,'f':3,'pa':0,'d':1})
def reach(w,A):
    # Fracción de activaciones en que el arma llega a disparar: alcance + movimiento
    r=w['alcance']+A['stats']['mov']
    return min(1.0, r/30)
def shoot(A,D):
    w=ranged(A)
    if not w: return 0
    if w.get('modo')=='dispersion': return kills(A,dict(w,a=1),D,n_att=2,auto=True)
    mod = 0.5 if 'firmes' in A['habilidades'] else 0
    base=kills(A,w,D,auto=w.get('modo')=='automatico')
    up=kills(A,w,D,auto=w.get('modo')=='automatico',hitmod=1)
    # Cobertura: la mitad de las veces -1, salvo ojo de halcón o automático
    cov = 1 if ('ojo_de_halcon' in A['habilidades'] or w.get('modo')=='automatico') else 0.5
    down=kills(A,w,D,hitmod=-1) if cov<1 else base
    v = base*(1-mod)+up*mod
    return (v*cov + down*(1-cov)) * reach(w,A)
def fight(A,D):
    fb=1 if 'carga_devastadora' in A['habilidades'] else 0
    k=kills(A,melee(A),D,fbonus=fb)
    reachw = min(1.0,(A['stats']['mov']+(5 if 'asalto' in A['habilidades'] else 3))/14)
    return k*reachw*0.7
res=[]
for a in ids:
    A=U[a]
    off=sum(max(shoot(A,U[d]),fight(A,U[d]))/U[d]['soldados']*U[d]['coste'] for d in ids)/len(ids)
    lost=sum(shoot(U[x],A)/A['soldados'] for x in ids if ranged(U[x]))/len(ids)
    dur=1/lost
    res.append((a,A['coste'],off,dur,off*dur))
# Ley cuadrática: el poder de combate crece con el cuadrado del coste.
k=sum(p/c**2 for a,c,o,d,p in res)/len(res)
print(f"{'perfil':13}{'coste':>6}{'ataque':>8}{'aguante':>9}{'valor':>8}{'coste justo':>13}")
for a,c,o,d,p in sorted(res,key=lambda x:-(x[4]/x[1]**2)):
    fair=(p/k)**0.5
    print(f"{a:13}{c:>6}{o:>8.1f}{d:>9.1f}{(p/c**2)/k:>8.2f}{round(fair/5)*5:>13}")
