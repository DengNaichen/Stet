"""Channel-first SAN-M graph using 1x1 convolutions and per-head attention.

Layout follows Apple's public ml-ane-transformers guidance. The host supplies
positioned features and masks so no data-dependent shape computation is traced.
"""
import torch
from torch import nn
from torch.nn import functional as F

class Projection(nn.Module):
    def __init__(self, linear):
        super().__init__()
        self.weight = nn.Parameter(linear.weight.detach().reshape(*linear.weight.shape,1,1))
        self.bias = linear.bias
    def forward(self,x):
        return F.conv2d(x,self.weight,self.bias)

class ChannelNorm(nn.Module):
    def __init__(self,norm):
        super().__init__()
        self.weight=nn.Parameter(norm.weight.detach().reshape(1,-1,1,1))
        self.bias=nn.Parameter(norm.bias.detach().reshape(1,-1,1,1))
        self.eps=norm.eps
    def forward(self,x):
        centered=x-x.mean(dim=1,keepdim=True)
        variance=(centered*centered).mean(dim=1,keepdim=True)
        return centered*torch.rsqrt(variance+self.eps)*self.weight+self.bias

class Attention(nn.Module):
    def __init__(self,source):
        super().__init__()
        self.dim=source.d_k*source.n_head
        self.head_dim=source.d_k
        self.sanm=hasattr(source,'linear_q_k_v')
        if self.sanm:
            self.qkv=Projection(source.linear_q_k_v)
            self.memory_weight=nn.Parameter(source.fsmn_block.weight.detach().unsqueeze(2))
            self.pad=(self.memory_weight.shape[-1]-1)//2
        else:
            self.q=Projection(source.linear_q)
            self.k=Projection(source.linear_k)
            self.v=Projection(source.linear_v)
        self.out=Projection(source.linear_out)
    def forward(self,x,valid,attention_bias):
        if self.sanm:
            q,k,v=self.qkv(x).split(self.dim,dim=1)
            v=v*valid
            memory=(F.conv2d(v,self.memory_weight,padding=(0,self.pad),groups=self.dim)+v)*valid
        else:
            q,k,v=self.q(x),self.k(x),self.v(x)
        qs=(q*(self.head_dim**-0.5)).split(self.head_dim,dim=1)
        ks=k.transpose(1,3).split(self.head_dim,dim=3)
        vs=v.split(self.head_dim,dim=1)
        outputs=[]
        for qi,ki,vi in zip(qs,ks,vs):
            scores=torch.einsum('bchq,bkhc->bkhq',qi,ki)+attention_bias
            weights=torch.softmax(scores,dim=1)
            outputs.append(torch.einsum('bkhq,bchk->bchq',weights,vi))
        out=self.out(torch.cat(outputs,dim=1))
        return out+memory if self.sanm else out

class Layer(nn.Module):
    def __init__(self,source):
        super().__init__()
        self.norm1=ChannelNorm(source.norm1)
        self.norm2=ChannelNorm(source.norm2)
        self.attention=Attention(source.self_attn)
        self.w1=Projection(source.w_1)
        self.w2=Projection(source.w_2)
        self.residual=getattr(source,'residual',True)
    def forward(self,x,valid,bias):
        attention=self.attention(self.norm1(x),valid,bias)
        x=x+attention if self.residual else attention
        return x+self.w2(F.relu(self.w1(self.norm2(x))))

class ANEEncoder(nn.Module):
    def __init__(self,source):
        super().__init__()
        self.layers=nn.ModuleList([Layer(source.encoders0)]+[Layer(x) for x in source.encoders])
        self.after_norm=ChannelNorm(source.after_norm)
        self.tp_layers=nn.ModuleList([Layer(x) for x in source.tp_encoders])
        self.tp_norm=ChannelNorm(source.tp_norm)
        self.linear1=Projection(source.linear1)
        self.linear2=Projection(source.linear2)
        self.blocks=nn.ModuleList([Layer(x) for x in source.blocks])
    def forward(self,positioned_features,valid_mask,attention_bias):
        x=positioned_features
        for layer in self.layers: x=layer(x,valid_mask,attention_bias)
        x=self.after_norm(x)
        for layer in self.tp_layers: x=layer(x,valid_mask,attention_bias)
        x=self.tp_norm(x)
        x=self.linear2(F.relu(self.linear1(x)))
        for layer in self.blocks: x=layer(x,valid_mask,attention_bias)
        return x
